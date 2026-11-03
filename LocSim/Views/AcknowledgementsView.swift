import SwiftUI

struct AcknowledgementsView: View {
    @State private var showingRepository = false
    private let repository = URL(string: "https://github.com/jkcoxson/idevice")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("idevice")
                    .font(.headline)
                Button("github.com/jkcoxson/idevice") {
                    showingRepository = true
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
                Link("github.com/SideStore/StosVPN", destination: URL(string: "https://github.com/SideStore/StosVPN")!)
                    .font(.subheadline)
                Text(verbatim: Self.stosVPNLicense)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .sheet(isPresented: $showingRepository) {
            SafariView(url: repository).ignoresSafeArea()
        }
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
