# Third-Party Notices

LocSim links the following software into the app binary.

## idevice

<https://github.com/jkcoxson/idevice>, distributed as `IDevice.xcframework`
(downloaded at build time, not part of this repository).

```
Copyright 2026 Jackson Coxson

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

idevice itself depends on further Rust crates under MIT and/or Apache-2.0
licenses; see the idevice repository for the full dependency list.

## Developer Disk Image

Not shipped with the app. When the image is missing, LocSim downloads it at
runtime from <https://github.com/doronz88/DeveloperDiskImage>. The image is
Apple software and subject to Apple's terms.
