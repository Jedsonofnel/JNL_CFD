# Licence

Unless otherwise stated, the original JNLCFD source code in this repository is
licensed under the MIT Licence.

This licence applies to the original code written for JNLCFD, including the C
source files, Lua source files, showcase scripts, tests, and documentation,
except where a file or third-party dependency states otherwise.

## MIT Licence

Copyright (c) 2026 Jed Nelson

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files, excluding third-party
components described below, to deal in the software without restriction,
including without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the software, subject to the
following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Third-party components

This repository uses third-party software. Those components remain under their
own licences and copyright notices.

### Triangle

The mesh generator Triangle is written by Jonathan Richard Shewchuk and is
copyrighted by its author. Triangle is freely available for private, research,
and institutional use, but its licence restricts commercial sale or inclusion
in commercial products without a separate licence or direct arrangement with
the author.

If Triangle is included as a vendored submodule or source dependency in this
repository, the Triangle source code and any modifications to it are not
covered by the MIT licence above. Users and redistributors must comply with
Triangle's own licence terms.

For details, see the copyright and licence notice distributed with Triangle,
and the Triangle project page:

<https://www.cs.cmu.edu/~quake/triangle.html>

### Fennel

Fennel is included or built as a third-party dependency. It remains under its
own licence. See the Fennel project and vendored source for the applicable
licence terms.

### Lua, raylib, readline, and system libraries

JNLCFD links against Lua, raylib, readline, and standard system libraries.
These dependencies remain under their respective licences. Installing, linking,
or redistributing binaries may require compliance with those licences in
addition to this one.

## Practical note for reviewers

The repository is intended for academic review, reproduction of the report
figures, and research use. Commercial use or redistribution of a combined
package containing Triangle may require separate permission for Triangle.
