import SwiftUI

struct AcknowledgementsView: View {
    @State private var shownPage: WebPage?
    private let idevice = URL(string: "https://github.com/jkcoxson/idevice")!
    private let stosVPN = URL(string: "https://github.com/SideStore/StosVPN")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: "idevice")
                    .font(.headline)
                Button {
                    shownPage = WebPage(url: idevice)
                } label: {
                    Text(verbatim: "github.com/jkcoxson/idevice")
                }
                .font(.subheadline)
                Text(Self.ideviceLicense)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(verbatim: "StosVPN")
                    .font(.headline)
                    .padding(.top, 12)
                Text("LocSim's local connection is based on StosVPN.")
                    .font(.subheadline)
                Button {
                    shownPage = WebPage(url: stosVPN)
                } label: {
                    Text(verbatim: "github.com/SideStore/StosVPN")
                }
                .font(.subheadline)
                Text(verbatim: Self.stosVPNLicense)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                NavigationLink {
                    RustLicensesView()
                } label: {
                    Label("Rust Libraries in idevice", systemImage: "doc.text")
                }
                .font(.subheadline)
                .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .webPageSheet($shownPage)
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static let stosVPNLicense = """
StosVPN License

Copyright (c) 2025 SideStore Team

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

**Attribution is clearly given** to the original project and author(s) in a prominent place (e.g., README, About page, or documentation).

Any derived project **must clearly state** that it is **based on** or **uses code from** the original project.

Redistribution, rebranding, or publishing of the **entire project** (or a substantially similar copy) under the same or similar name or branding, **without explicit written permission**, is **prohibited**.

This clause is intended to prevent unauthorized re-uploads, clones, or misrepresentation of the original work.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
"""

    private static let ideviceLicense = """
Copyright 2026 Jackson Coxson

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
"""
}

/// Licenses of the Rust crates compiled into IDevice.xcframework, from THIRD_PARTY_LICENSES.md.
private struct RustLicensesView: View {
    private let paragraphs: [String] = {
        guard let url = Bundle.main.url(forResource: "THIRD_PARTY_LICENSES", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "\n\n")
    }()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(verbatim: paragraph)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Rust Libraries")
        .navigationBarTitleDisplayMode(.inline)
    }
}

