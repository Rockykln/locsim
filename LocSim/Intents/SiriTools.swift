// Siri AI can call these actions as tools. SIRI_AI is set only for builds with the iOS 27.3 SDK
// or later (see project.yml), so a build with an older SDK does not contain this at all.
#if SIRI_AI
import AppIntents

// Set Last Location (Control Center) and the Live Activity's Clear button stay out: they would
// duplicate these and leave Siri two ways to do the same thing.
@available(iOS 27.3, *)
extension SetFavoriteIntent: ToolIntent {}

@available(iOS 27.3, *)
extension SetPlaceIntent: ToolIntent {}

@available(iOS 27.3, *)
extension SetCoordinatesIntent: ToolIntent {}

@available(iOS 27.3, *)
extension ClearLocationIntent: ToolIntent {}
#endif
