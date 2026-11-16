/// The API base URL (the stack's ApiBaseUrl output), set when running or building:
///   flutter run -d chrome --dart-define=PEN_API=https://abc123.execute-api.us-east-1.amazonaws.com
/// Empty when it wasn't passed.
const penApi = String.fromEnvironment('PEN_API');
