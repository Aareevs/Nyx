# Security policy

## Supported versions

Only the latest release of Nyx gets security fixes. Please update to the
[latest release](https://github.com/Aareevs/Nyx/releases/latest) before
reporting, in case the problem is already fixed.

## Reporting a vulnerability

Please do not open a public issue for a security problem.

Report it privately instead: on the repository page open **Security**, then
**Report a vulnerability**. That opens a private thread with the maintainer that
only the two of you can see.

A good report says:

- what the problem is and what it could let someone do,
- the Nyx version and macOS version,
- the steps to reproduce it, or a short proof of concept.

You can expect a first reply within about a week. Nyx is a spare-time project, so
a fix can take longer, but you will be told where it stands. Once a fix is
released, you are welcome to be credited in the release notes if you want.

## What counts

Anything that could expose your data or let another app or person act through
Nyx without your say-so. For example:

- a feature reading or sending something that the
  [privacy notes](docs/PRIVACY.md) do not say it does,
- using one of Nyx's permissions (see [permissions](docs/PERMISSIONS.md)) for
  something the feature should not do,
- a way to make Nyx run code or commands it was not asked to,
- a flaw in the updater or in how a download is checked.

Ordinary bugs, crashes and feature requests belong in the
[issue tracker](https://github.com/Aareevs/Nyx/issues).

## About downloads

Nyx releases are not signed with a paid Apple Developer ID, so macOS asks you to
use **Open Anyway** once. Only download Nyx from this repository's
[releases page](https://github.com/Aareevs/Nyx/releases), and compare the
checksum shown there if you want to be sure the file is untouched.
