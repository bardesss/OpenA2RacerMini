# Security

OpenA2RacerMini reads game data (CD folders and disc images) supplied by the
player. Bugs where crafted data crashes the game or does something it should
not are security bugs, and so is anything in the Onion package or launcher
that touches files outside the port's own folder.

## Reporting

Please report security problems privately through GitHub:
**Security → Report a vulnerability** on
[bardesss/OpenA2RacerMini](https://github.com/bardesss/OpenA2RacerMini/security/advisories/new).
Don't open a public issue for them.

Problems in the engine itself also affect upstream
[3dutchie/openA2Racer](https://github.com/3dutchie/openA2Racer); we pass
those on once there is a fix.

## Supported versions

Only the latest release and `main` get fixes.
