# Third-Party Notices

LocSim includes or is based on the following software.

## idevice

<https://github.com/jkcoxson/idevice>, distributed as `IDevice.xcframework`
(downloaded at build time, not part of this repository).

```
Copyright 2026 Jackson Coxson

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

The framework statically contains further Rust crates, among them rustls, aws-lc-rs
and aws-lc-sys (AWS-LC, derived from BoringSSL and OpenSSL) and ring, under MIT,
Apache-2.0, ISC, BSD-3-Clause and CDLA-Permissive-2.0. The full list with versions,
copyright notices and license texts is in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

## StosVPN

<https://github.com/SideStore/StosVPN>. The local tunnel in `LocSimTunnel/` is based on
StosVPN.

```
StosVPN License

Copyright (c) 2025 SideStore Team

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

**Attribution is clearly given** to the original project and author(s) in a prominent place (e.g., README, About page, or documentation).

Any derived project **must clearly state** that it is **based on** or **uses code from** the original project.

Redistribution, rebranding, or publishing of the **entire project** (or a substantially similar copy) under the same or similar name or branding, **without explicit written permission**, is **prohibited**.

This clause is intended to prevent unauthorized re-uploads, clones, or misrepresentation of the original work.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

## Developer Disk Image

Not shipped with the app. When the image is missing, LocSim downloads it at
runtime from <https://github.com/doronz88/DeveloperDiskImage>. The image is
Apple software and subject to Apple's terms.
