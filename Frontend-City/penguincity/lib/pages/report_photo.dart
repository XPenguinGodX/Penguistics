import 'package:flutter/material.dart';
import 'package:penguincity/services/city_reports.dart';

class ReportPhoto extends StatefulWidget {
  const ReportPhoto({super.key, required this.loadUrl});
  final Future<String> Function() loadUrl;
  @override
  State<ReportPhoto> createState() => _ReportPhotoState();
}

class _ReportPhotoState extends State<ReportPhoto> {
  late Future<String> _url;
  @override
  void initState() {
    super.initState();
    _url = Future.sync(widget.loadUrl);
  }

  Widget _error(String message) => Column(
    children: [
      Text(message),
      TextButton.icon(
        onPressed: () => setState(() {
          _url = Future.sync(widget.loadUrl);
        }),
        icon: const Icon(Icons.refresh),
        label: const Text('Retry photo'),
      ),
    ],
  );

  Widget _image(String url, {bool enlarged = false}) => Image.network(
    url,
    fit: BoxFit.contain,
    semanticLabel: 'Submitted road damage photo',
    loadingBuilder: (context, child, progress) => progress == null
        ? child
        : const Center(child: CircularProgressIndicator()),
    errorBuilder: (context, error, stack) => enlarged
        ? const Text('Photo could not be displayed. Close and retry the photo.')
        : _error('Photo could not be displayed. Retry to get a fresh link.'),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _url,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const SizedBox(
          height: 180,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (snapshot.hasError) {
        final error = snapshot.error;
        return _error(
          error is CityReportsException
              ? error.message
              : 'Could not load the photo.',
        );
      }
      final url = snapshot.data!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 180, child: _image(url)),
          TextButton.icon(
            icon: const Icon(Icons.zoom_in),
            label: const Text('Enlarge photo'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => Dialog(
                child: SizedBox(
                  width: 900,
                  height: MediaQuery.sizeOf(context).height * .8,
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          tooltip: 'Close photo',
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      Expanded(
                        child: InteractiveViewer(
                          minScale: 1,
                          maxScale: 5,
                          child: _image(url, enlarged: true),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
