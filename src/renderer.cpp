#include "renderer.hpp"
#include "render_workers.hpp"
#include <array>
#include <cctype>
#include <cmath>
#include <fstream>
#include <limits>

namespace a2 {
void Camera::lookAt(Vec3 eye, Vec3 target) {
  position = eye;
  forward = normalized(target - eye);
  right = normalized(cross({0, 1, 0}, forward));
  up = cross(forward, right);
}
Renderer::Renderer() : color_(width * height), depth_(width * height) {}
void Renderer::clear(uint32_t color) {
  if (scaledWorld()) {
    std::fill(world_.begin(), world_.end(), color);
    worldPending_ = true;
  } else {
    std::fill(color_.begin(), color_.end(), color);
  }
  std::fill(depth_.begin(), depth_.end(), 0);
  triangles_ = 0;
  commands_.clear();
  for (auto &band : bands_)
    band.clear();
  ++frame_;
}
int Renderer::worldWidth() const { return int(std::lround(width * worldScale_)); }
int Renderer::worldHeight() const { return int(std::lround(height * worldScale_)); }
void Renderer::setWorldScale(float scale) {
  if (enhanced_)
    return;
  scale = std::isfinite(scale) ? std::clamp(scale, .5f, 1.f) : 1.f;
  if (scale == worldScale_)
    return;
  // Reserve the largest size once so later scale changes never reallocate or throw.
  world_.reserve(size_t(width) * height);
  depth_.reserve(size_t(width) * height);
  worldScale_ = scale;
  worldW_ = worldWidth();
  worldH_ = worldHeight();
  world_.resize(scaledWorld() ? size_t(worldW_) * worldH_ : 0);
  depth_.resize(size_t(worldW_) * worldH_);
  worldPending_ = false;
  commands_.clear();
  for (auto &band : bands_)
    band.clear();
}
// Blends 8-bit channels as two 16-bit lanes; f is the weight of b, 0..256.
static inline uint32_t lerpPixel(uint32_t a, uint32_t b, uint32_t f) {
  const uint32_t g = 256 - f;
  const uint32_t rb = (((a & 0x00ff00ffu) * g + (b & 0x00ff00ffu) * f) >> 8) & 0x00ff00ffu;
  const uint32_t ag = (((a >> 8) & 0x00ff00ffu) * g + ((b >> 8) & 0x00ff00ffu) * f) & 0xff00ff00u;
  return rb | ag;
}
void Renderer::resolveWorld() {
  if (!worldPending_)
    return;
  worldPending_ = false;
  // Fixed-point bilinear upscale of the world buffer into the 640x480 frame.
  // Destination pixel centres map to 16.16 source positions, clamped at edges.
  struct Tap {
    uint16_t i0, i1, f;
  };
  auto taps = [](int src, int dst, Tap *out) {
    const int32_t step = int32_t((int64_t(src) << 16) / dst);
    for (int i = 0; i < dst; ++i) {
      int32_t p = i * step + step / 2 - 32768;
      if (p < 0)
        p = 0;
      const int i0 = std::min(src - 1, int(p >> 16));
      out[i] = {uint16_t(i0), uint16_t(std::min(src - 1, i0 + 1)), uint16_t((p >> 8) & 255)};
    }
  };
  std::array<Tap, width> xs;
  std::array<Tap, height> ys;
  taps(worldW_, width, xs.data());
  taps(worldH_, height, ys.data());
  const uint32_t *const source = world_.data();
  uint32_t *const frame = color_.data();
  const size_t stride = size_t(worldW_);
  parallelRenderRows(height, 32, [&](int begin, int end) {
    for (int y = begin; y < end; ++y) {
      const Tap ty = ys[size_t(y)];
      const uint32_t *r0 = source + ty.i0 * stride, *r1 = source + ty.i1 * stride;
      uint32_t *out = frame + size_t(y) * width;
      if (ty.f == 0) {
        for (int x = 0; x < width; ++x) {
          const Tap tx = xs[size_t(x)];
          out[x] = lerpPixel(r0[tx.i0], r0[tx.i1], tx.f);
        }
        continue;
      }
      for (int x = 0; x < width; ++x) {
        const Tap tx = xs[size_t(x)];
        out[x] = lerpPixel(lerpPixel(r0[tx.i0], r0[tx.i1], tx.f),
                           lerpPixel(r1[tx.i0], r1[tx.i1], tx.f), ty.f);
      }
    }
  });
}
void Renderer::background(const Image &sky, float heading, float horizon) {
  const int width = worldW_, height = worldH_;
  // Exactly 1 or 2 (the enhanced scale) unless the world scale is reduced.
  const float rowScale = float(worldH_) / Renderer::height;
  int limit = std::clamp(int((horizon + 30) * rowScale), 0, height);
  uint32_t *const target = worldColor();
  const FilteredTexture *filter =
      enhanced_ && !sky.pixels.empty() ? &filtered(sky, false) : nullptr;
  auto rows = [&](int begin, int end) {
    for (int y = begin; y < end; ++y) {
      for (int x = 0; x < width; ++x) {
        uint32_t color;
        if (y < limit && !sky.pixels.empty()) {
          int sx = (int(x * float(sky.width) / width + heading * sky.width / (2 * pi)) % sky.width +
                    sky.width) %
                   sky.width;
          int sy = std::clamp(int(float(y) * sky.height / std::max(1, limit)), 0, sky.height - 1);
          color = filter ? filter->sample(float(x) / width + heading / (2 * pi),
                                          std::min(.9999f, float(y) / std::max(1, limit)), 0)
                         : sky.pixels[size_t(sy) * sky.width + sx];
        } else {
          int g = 70 + int(25.0f * (height - y) / height);
          color = 0xff000000u | (uint32_t(g / 2) << 16) | (uint32_t(g) << 8) | uint32_t(g / 3);
        }
        target[size_t(y) * width + x] = color;
      }
    }
  };
  if (enhanced_ || scaledWorld())
    parallelRenderRows(height, 32, rows);
  else
    rows(0, height);
}
static uint32_t shade(uint32_t c, float l, float fog, uint32_t tint) {
  const int r = std::clamp(int(((c >> 16) & 255) * l * ((tint >> 16) & 255) / 255.0f), 0, 255);
  const int g = std::clamp(int(((c >> 8) & 255) * l * ((tint >> 8) & 255) / 255.0f), 0, 255);
  const int b = std::clamp(int((c & 255) * l * (tint & 255) / 255.0f), 0, 255);
  return 0xff000000u | (uint32_t(lerp(float(r), 155, fog)) << 16) |
         (uint32_t(lerp(float(g), 175, fog)) << 8) | uint32_t(lerp(float(b), 183, fog));
}
void Renderer::triangle(const Camera &cam, DrawVertex a, DrawVertex b, DrawVertex c,
                        const Image *texture, uint32_t color, bool mask, float light, bool blend) {
  const int width = worldW_, height = worldH_;
  // The focal length follows the world size: x2 enhanced, x(worldWidth/640) scaled.
  const float focal = cam.focal * (float(worldW_) / Renderer::width);
  struct CV {
    float x, y, z, u, v, light, alpha;
  };
  std::array<CV, 6> input{}, output{};
  std::array<DrawVertex, 3> vertices{a, b, c};
  for (int i = 0; i < 3; ++i) {
    auto d = vertices[i].position - cam.position;
    input[i] = {dot(d, cam.right), dot(d, cam.up),    dot(d, cam.forward), vertices[i].uv.x,
                vertices[i].uv.y,  vertices[i].light, vertices[i].alpha};
  }
  int count = 3;
  for (int plane = 0; plane < 2; ++plane) {
    int n = 0;
    auto inside = [&](CV v) { return plane == 0 ? v.z >= cam.nearPlane : v.z <= cam.farPlane; };
    for (int i = 0; i < count; ++i) {
      CV p = input[i], q = input[(i + 1) % count];
      bool ip = inside(p), iq = inside(q);
      if (ip)
        output[n++] = p;
      if (ip != iq) {
        float z = plane == 0 ? cam.nearPlane : cam.farPlane, t = (z - p.z) / (q.z - p.z);
        output[n++] = {lerp(p.x, q.x, t),        lerp(p.y, q.y, t), z,
                       lerp(p.u, q.u, t),        lerp(p.v, q.v, t), lerp(p.light, q.light, t),
                       lerp(p.alpha, q.alpha, t)};
      }
    }
    if (n < 3)
      return;
    input = output;
    count = n;
  }
  auto project = [&](CV v) {
    float q = 1 / v.z;
    return Projected{width * 0.5f + focal * v.x * q,
                     height * 0.5f - focal * v.y * q,
                     q,
                     v.u * q,
                     v.v * q,
                     v.light * q,
                     v.alpha * q};
  };
  for (int i = 1; i < count - 1; ++i) {
    Projected pa = project(input[0]), pb = project(input[i]), pc = project(input[i + 1]);
    if (!enhanced_) {
      raster(pa, pb, pc, texture, color, mask, light, cam.farPlane, blend, 0, height, nullptr);
      continue;
    }
    if (!std::isfinite(pa.x) || !std::isfinite(pa.y) || !std::isfinite(pb.x) ||
        !std::isfinite(pb.y) || !std::isfinite(pc.x) || !std::isfinite(pc.y))
      continue;
    float minY = std::min({pa.y, pb.y, pc.y}), maxY = std::max({pa.y, pb.y, pc.y});
    if (maxY < 0 || minY >= height || std::max({pa.x, pb.x, pc.x}) < 0 ||
        std::min({pa.x, pb.x, pc.x}) >= width)
      continue;
    float area = (pb.x - pa.x) * (pc.y - pa.y) - (pb.y - pa.y) * (pc.x - pa.x);
    if (!std::isfinite(area) || std::abs(area) < .001f)
      continue;
    const auto *filter = texture && !texture->pixels.empty() ? &filtered(*texture, mask) : nullptr;
    size_t command = commands_.size();
    commands_.push_back({pa, pb, pc, texture, filter, color, mask, blend, light, cam.farPlane});
    triangles_.fetch_add(1, std::memory_order_relaxed);
    int first = int(std::clamp(minY, 0.f, float(height - 1))) / 32;
    int last = int(std::clamp(std::ceil(maxY), 0.f, float(height - 1))) / 32;
    for (int band = first; band <= last; ++band)
      bands_[size_t(band)].push_back(command);
  }
}
void Renderer::flushWorld() {
  if (commands_.empty())
    return;
  parallelRenderRows(worldH_, 32, [&](int begin, int end) {
    for (size_t index : bands_[size_t(begin / 32)]) {
      const auto &c = commands_[index];
      raster(c.a, c.b, c.c, c.texture, c.tint, c.mask, c.light, c.farPlane, c.blend, begin, end,
             c.filter);
    }
  });
  commands_.clear();
  for (auto &band : bands_)
    band.clear();
}
void Renderer::raster(Projected a, Projected b, Projected c, const Image *texture, uint32_t tint,
                      bool mask, float light, float farPlane, bool blend, int rowBegin, int rowEnd,
                      const FilteredTexture *filter) {
  const int width = worldW_, height = worldH_;
  uint32_t *const target = worldColor();
  for (const auto &v : {a, b, c})
    if (!std::isfinite(v.x) || !std::isfinite(v.y) || !std::isfinite(v.q) || !std::isfinite(v.u) ||
        !std::isfinite(v.v))
      return;
  auto edge = [](Projected p, Projected q, float x, float y) {
    return (q.x - p.x) * (y - p.y) - (q.y - p.y) * (x - p.x);
  };
  float area = edge(a, b, c.x, c.y);
  if (!std::isfinite(area) || std::abs(area) < 0.001f)
    return;
  if (area < 0) {
    std::swap(b, c);
    area = -area;
  }
  float x0 = std::min({a.x, b.x, c.x}), x1 = std::max({a.x, b.x, c.x}),
        y0 = std::min({a.y, b.y, c.y}), y1 = std::max({a.y, b.y, c.y});
  if (x1 < 0 || y1 < 0 || x0 >= width || y0 >= height)
    return;
  int minX = int(std::floor(std::clamp(x0, 0.0f, float(width - 1)))),
      maxX = int(std::ceil(std::clamp(x1, 0.0f, float(width - 1))));
  int minY = int(std::floor(std::clamp(y0, 0.0f, float(height - 1)))),
      maxY = int(std::ceil(std::clamp(y1, 0.0f, float(height - 1))));
  minY = std::max(minY, rowBegin);
  maxY = std::min(maxY, rowEnd - 1);
  if (minX > maxX || minY > maxY)
    return;
  if (!enhanced_)
    triangles_.fetch_add(1, std::memory_order_relaxed);
  float inv = 1 / area;
  const float dx0 = -(c.y - b.y) * inv, dx1 = -(a.y - c.y) * inv, dx2 = -(b.y - a.y) * inv;
  const float dy0 = (c.x - b.x) * inv, dy1 = (a.x - c.x) * inv, dy2 = (b.x - a.x) * inv;
  const float uqx = dx0 * a.u + dx1 * b.u + dx2 * c.u, vqx = dx0 * a.v + dx1 * b.v + dx2 * c.v;
  const float uqy = dy0 * a.u + dy1 * b.u + dy2 * c.u, vqy = dy0 * a.v + dy1 * b.v + dy2 * c.v;
  const float qx = dx0 * a.q + dx1 * b.q + dx2 * c.q, qy = dy0 * a.q + dy1 * b.q + dy2 * c.q;
  auto topLeft = [](Projected p, Projected q) { return q.y < p.y || (q.y == p.y && q.x > p.x); };
  const bool edge0 = topLeft(b, c), edge1 = topLeft(c, a), edge2 = topLeft(a, b);
  for (int y = minY; y <= maxY; ++y) {
    float w0 = edge(b, c, float(minX) + 0.5f, float(y) + 0.5f) * inv,
          w1 = edge(c, a, float(minX) + 0.5f, float(y) + 0.5f) * inv, w2 = 1 - w0 - w1;
    size_t index = size_t(y) * width + minX;
    float lod = 0, majorU = 0, majorV = 0;
    int taps = 1;
    for (int x = minX; x <= maxX; ++x, ++index, w0 += dx0, w1 += dx1, w2 += dx2) {
      if (w0 < -0.00001f || w1 < -0.00001f || w2 < -0.00001f)
        continue;
      // Shared edges belong to one blended triangle, avoiding dark fan seams.
      if (blend &&
          ((w0 <= .00001f && !edge0) || (w1 <= .00001f && !edge1) || (w2 <= .00001f && !edge2)))
        continue;
      float q = w0 * a.q + w1 * b.q + w2 * c.q;
      if (q <= depth_[index])
        continue;
      uint32_t color = 0xffffffffu;
      if (texture && !texture->pixels.empty()) {
        float u = (w0 * a.u + w1 * b.u + w2 * c.u) / q, v = (w0 * a.v + w1 * b.v + w2 * c.v) / q;
        if (!std::isfinite(u) || !std::isfinite(v))
          continue;
        if (filter) {
          // Perspective footprints vary slowly within eight-pixel scanline blocks.
          // Up to four samples along the major axis keep grazing road markings
          // sharp without undersampling their long, thin footprints.
          if (x == minX || (x & 7) == 0) {
            float dudx = (uqx - u * qx) / q, dvdx = (vqx - v * qx) / q;
            float dudy = (uqy - u * qy) / q, dvdy = (vqy - v * qy) / q;
            float rx = std::hypot(dudx * filter->width(), dvdx * filter->height());
            float ry = std::hypot(dudy * filter->width(), dvdy * filter->height());
            float major = std::max(rx, ry), minor = std::max(1.f, std::min(rx, ry));
            taps = major > minor * 3 ? 4 : (major > minor * 1.5f ? 2 : 1);
            majorU = rx > ry ? dudx : dudy;
            majorV = rx > ry ? dvdx : dvdy;
            lod = std::log2(std::max(1.f, std::max(minor, major / taps)));
          }
          auto sample = [&](float su, float sv, float sl) {
            return filter->sample(su, sv, sl, {u, v});
          };
          if (taps == 1)
            color = sample(u, v, lod);
          else if (taps == 2)
            color = mixColor(sample(u - majorU * .25f, v - majorV * .25f, lod),
                             sample(u + majorU * .25f, v + majorV * .25f, lod), .5f);
          else {
            auto a = mixColor(sample(u - majorU * .375f, v - majorV * .375f, lod),
                              sample(u - majorU * .125f, v - majorV * .125f, lod), .5f);
            auto b = mixColor(sample(u + majorU * .125f, v + majorV * .125f, lod),
                              sample(u + majorU * .375f, v + majorV * .375f, lod), .5f);
            color = mixColor(a, b, .5f);
          }
          if (mask) {
            unsigned alpha = color >> 24;
            if (alpha < 128)
              continue;
            // Unpremultiply opaque cutout samples after all filtering.
            color = 0xff000000u | (std::min(255u, ((color >> 16) & 255) * 255 / alpha) << 16) |
                    (std::min(255u, ((color >> 8) & 255) * 255 / alpha) << 8) |
                    std::min(255u, (color & 255) * 255 / alpha);
          }
        } else {
          u = std::fmod(u, 1.0f);
          v = std::fmod(v, 1.0f);
          if (u < 0)
            u += 1;
          if (v < 0)
            v += 1;
          int tx = std::min(texture->width - 1, int(u * texture->width));
          int ty = std::min(texture->height - 1, int(v * texture->height));
          size_t p = size_t(ty) * texture->width + tx;
          if (mask && !texture->indices.empty() && texture->indices[p] == 0)
            continue;
          color = texture->pixels[p];
        }
      }
      float fog = std::clamp((1 / q - farPlane * 0.48f) / (farPlane * 0.52f), 0.0f, 0.92f);
      float illumination = light * (w0 * a.light + w1 * b.light + w2 * c.light) / q;
      auto shaded = shade(color, illumination, fog, tint);
      if (blend) {
        float alpha = std::clamp((w0 * a.alpha + w1 * b.alpha + w2 * c.alpha) / q, 0.f, 1.f);
        // Shadow overlays test ground depth but do not replace it.
        target[index] = mixColor(target[index], shaded, alpha * (1 - fog));
      } else {
        target[index] = shaded;
        depth_[index] = q;
      }
    }
  }
}
void Renderer::quad(const Camera &c, Vec3 a, Vec3 b, Vec3 d, Vec3 e, const Image *t, float us,
                    float vs, uint32_t color) {
  triangle(c, {a, {0, 0}}, {b, {us, 0}}, {d, {us, vs}}, t, color);
  triangle(c, {a, {0, 0}}, {d, {us, vs}}, {e, {0, vs}}, t, color);
}
void Renderer::mesh(const Camera &cam, const Mesh &mesh, const Image &texture, Vec3 pos, float yaw,
                    float scale, bool mask, bool cullBackFaces) {
  float s = std::sin(yaw), c = std::cos(yaw);
  std::vector<DrawVertex> vertices;
  vertices.reserve(mesh.vertices.size());
  for (auto &v : mesh.vertices) {
    auto p = v.position * scale;
    Vec3 n{v.normal.x * c + v.normal.z * s, v.normal.y, v.normal.z * c - v.normal.x * s};
    float light = enhanced_
                      ? .48f + .58f * std::abs(dot(normalized(n), normalized(Vec3{-.45f, 1, -.3f})))
                      : 1;
    vertices.push_back({pos + Vec3{p.x * c + p.z * s, p.y, p.z * c - p.x * s}, v.uv, light});
  }
  for (auto &f : mesh.faces) {
    auto a = vertices[f.indices[0]], b = vertices[f.indices[1]], c = vertices[f.indices[2]];
    Vec3 n = normalized(cross(b.position - a.position, c.position - a.position));
    if (cullBackFaces && dot(n, cam.position - a.position) <= 0)
      continue;
    float light =
        enhanced_ ? 1.f : 0.72f + 0.28f * std::abs(dot(n, normalized(Vec3{0.3f, 1, -0.4f})));
    triangle(cam, a, b, c, &texture, 0xffffffff, mask, light);
  }
}
void Renderer::rect(int x, int y, int w, int h, uint32_t c) {
  if (worldPending_)
    resolveWorld();
  const int width = pixelWidth(), height = pixelHeight();
  x *= scale_;
  y *= scale_;
  w *= scale_;
  h *= scale_;
  for (int j = std::max(0, y); j < std::min(height, y + h); ++j)
    for (int i = std::max(0, x); i < std::min(width, x + w); ++i)
      color_[size_t(j) * width + i] = c;
}
void Renderer::line(int x, int y, int xx, int yy, uint32_t c) {
  if (worldPending_)
    resolveWorld();
  const int width = pixelWidth(), height = pixelHeight();
  x *= scale_;
  y *= scale_;
  xx *= scale_;
  yy *= scale_;
  int dx = std::abs(xx - x), sx = x < xx ? 1 : -1, dy = -std::abs(yy - y), sy = y < yy ? 1 : -1,
      err = dx + dy;
  for (int limit = 0; limit < 10000; ++limit) {
    if (x >= 0 && x < width && y >= 0 && y < height)
      color_[size_t(y) * width + x] = c;
    if (x == xx && y == yy)
      break;
    int e = 2 * err;
    if (e >= dy) {
      err += dy;
      x += sx;
    }
    if (e <= dx) {
      err += dx;
      y += sy;
    }
  }
}
// Original code glyphs: 5x7 rows, independent of proprietary fonts.
static const char *glyph(char c) {
  switch (std::toupper(static_cast<unsigned char>(c))) {
  case 'A':
    return "01110100011000111111100011000110001";
  case 'B':
    return "11110100011000111110100011000111110";
  case 'C':
    return "01111100001000010000100001000001111";
  case 'D':
    return "11110100011000110001100011000111110";
  case 'E':
    return "11111100001000011110100001000011111";
  case 'F':
    return "11111100001000011110100001000010000";
  case 'G':
    return "01111100001000010111100011000101111";
  case 'H':
    return "10001100011000111111100011000110001";
  case 'I':
    return "11111001000010000100001000010011111";
  case 'J':
    return "00111000100001000010100101001001100";
  case 'K':
    return "10001100101010011000101001001010001";
  case 'L':
    return "10000100001000010000100001000011111";
  case 'M':
    return "10001110111010110101100011000110001";
  case 'N':
    return "10001110011010110011100011000110001";
  case 'O':
    return "01110100011000110001100011000101110";
  case 'P':
    return "11110100011000111110100001000010000";
  case 'Q':
    return "01110100011000110001101011001001101";
  case 'R':
    return "11110100011000111110101001001010001";
  case 'S':
    return "01111100001000001110000010000111110";
  case 'T':
    return "11111001000010000100001000010000100";
  case 'U':
    return "10001100011000110001100011000101110";
  case 'V':
    return "10001100011000110001100010101000100";
  case 'W':
    return "10001100011000110101101011101110001";
  case 'X':
    return "10001100010101000100010101000110001";
  case 'Y':
    return "10001100010101000100001000010000100";
  case 'Z':
    return "11111000010001000100010001000011111";
  case '0':
    return "01110100011001110101110011000101110";
  case '1':
    return "00100011000010000100001000010001110";
  case '2':
    return "01110100010000100010001000100011111";
  case '3':
    return "11110000010000101110000010000111110";
  case '4':
    return "00010001100101010010111110001000010";
  case '5':
    return "11111100001000011110000010000111110";
  case '6':
    return "01110100001000011110100011000101110";
  case '7':
    return "11111000010001000100010000100001000";
  case '8':
    return "01110100011000101110100011000101110";
  case '9':
    return "01110100011000101111000010000101110";
  case ':':
    return "00000001000010000000001000010000000";
  case '.':
    return "00000000000000000000000000010000100";
  case ',':
    return "00000000000000000000001000010001000";
  case '-':
    return "00000000000000011111000000000000000";
  case '/':
    return "00001000100001000100010000100010000";
  case '>':
    return "10000010000010000010001000100010000";
  case '<':
    return "00001000100010001000001000001000001";
  case '+':
    return "00000001000010011111001000010000000";
  case '!':
    return "00100001000010000100001000000000100";
  case '?':
    return "01110100010000100010001000000000100";
  case '%':
    return "11001110100001000100010001001100011";
  case '=':
    return "00000111110000011111000000000000000";
  default:
    return "00000000000000000000000000000000000";
  }
}
void Renderer::text(int x, int y, std::string_view value, uint32_t c, int scale) {
  int ox = x;
  for (char ch : value) {
    if (ch == '\n') {
      x = ox;
      y += 9 * scale;
      continue;
    }
    auto g = glyph(ch);
    for (int j = 0; j < 7; ++j)
      for (int i = 0; i < 5; ++i)
        if (g[j * 5 + i] == '1')
          rect(x + i * scale, y + j * scale, scale, scale, c);
    x += 6 * scale;
  }
}
void Renderer::blit(const Image &image, int x, int y, int w, int h, bool transparent) {
  if (transparent) {
    blitKey(image, x, y, 0, w, h);
    return;
  }
  if (worldPending_)
    resolveWorld();
  if (image.pixels.empty())
    return;
  if (w <= 0)
    w = image.width;
  if (h <= 0)
    h = image.height;
  const int width = pixelWidth(), height = pixelHeight();
  x *= scale_;
  y *= scale_;
  w *= scale_;
  h *= scale_;
  for (int yy = std::max(0, y); yy < std::min(height, y + h); ++yy)
    for (int xx = std::max(0, x); xx < std::min(width, x + w); ++xx) {
      int sx = (xx - x) * image.width / w, sy = (yy - y) * image.height / h;
      size_t src = size_t(sy) * image.width + sx;
      color_[size_t(yy) * width + xx] = image.pixels[src];
    }
}
void Renderer::blitKey(const Image &image, int x, int y, uint8_t key, int w, int h) {
  if (worldPending_)
    resolveWorld();
  if (image.pixels.empty())
    return;
  if (w <= 0)
    w = image.width;
  if (h <= 0)
    h = image.height;
  const int width = pixelWidth(), height = pixelHeight();
  x *= scale_;
  y *= scale_;
  w *= scale_;
  h *= scale_;
  for (int yy = std::max(0, y); yy < std::min(height, y + h); ++yy)
    for (int xx = std::max(0, x); xx < std::min(width, x + w); ++xx) {
      int sx = (xx - x) * image.width / w, sy = (yy - y) * image.height / h;
      size_t source = size_t(sy) * image.width + sx;
      if (!image.indices.empty() && image.indices[source] == key)
        continue;
      color_[size_t(yy) * width + xx] = image.pixels[source];
    }
}
void Renderer::sprite(const Sprite &sprite, int anchorX, int anchorY, uint8_t key) {
  blitKey(sprite.image, anchorX - sprite.hotspotX, anchorY - sprite.hotspotY, key);
}
void Renderer::dim(float amount) {
  if (worldPending_)
    resolveWorld();
  float factor = std::clamp(1 - amount, 0.0f, 1.0f);
  for (auto &c : color_)
    c = shade(c, factor, 0, 0xffffffff);
}
bool Renderer::saveBMP(const std::filesystem::path &path) const {
  const int width = pixelWidth(), height = pixelHeight();
  std::ofstream f(path, std::ios::binary);
  if (!f)
    return false;
  auto put16 = [&](uint16_t v) {
    f.put(char(v));
    f.put(char(v >> 8));
  };
  auto put32 = [&](uint32_t v) {
    put16(uint16_t(v));
    put16(uint16_t(v >> 16));
  };
  f.write("BM", 2);
  put32(54 + width * height * 3);
  put32(0);
  put32(54);
  put32(40);
  put32(width);
  put32(height);
  put16(1);
  put16(24);
  put32(0);
  put32(width * height * 3);
  put32(2835);
  put32(2835);
  put32(0);
  put32(0);
  for (int y = height - 1; y >= 0; --y)
    for (int x = 0; x < width; ++x) {
      uint32_t c = color_[size_t(y) * width + x];
      f.put(char(c));
      f.put(char(c >> 8));
      f.put(char(c >> 16));
    }
  return bool(f);
}
} // namespace a2
