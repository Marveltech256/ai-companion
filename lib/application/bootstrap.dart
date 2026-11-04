import 'package:flutter/material.dart';

import '../core/app_failure.dart';
import 'application.dart';
import 'connection.dart';
import 'theme.dart';

/// Shows a real loading/retry state while restoring the selected account.
class ApplicationBootstrap extends StatefulWidget {
  const ApplicationBootstrap({
    super.key,
    required this.open,
    this.connectCloud,
    this.openDevice,
    this.requireSignIn = true,
  });
  final Future<AppConnection> Function() open;
  final bool requireSignIn;
  final Future<AppConnection> Function()? connectCloud, openDevice;
  @override
  State<ApplicationBootstrap> createState() => _ApplicationBootstrapState();
}

class _ApplicationBootstrapState extends State<ApplicationBootstrap> {
  AppConnection? _connection;
  Object? _error;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _open(widget.open);
  }

  Future<void> _open(Future<AppConnection> Function() factory) async {
    final attempt = ++_attempt;
    setState(() => _error = null);
    try {
      final connection = await factory();
      if (!mounted || attempt != _attempt) {
        await connection.dispose();
        return;
      }
      setState(() => _connection = connection);
    } catch (error) {
      if (mounted && attempt == _attempt) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_connection != null) {
      return MorrowApplication(
        connection: _connection!,
        connectCloud: widget.connectCloud,
        useDevice: widget.openDevice,
        requireSignIn: widget.requireSignIn,
      );
    }
    return MaterialApp(
      title: 'Ai Companion',
      debugShowCheckedModeBanner: false,
      theme: morrowTheme(),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Brand(),
                    const SizedBox(height: 44),
                    const LumiOrb(size: 92),
                    const SizedBox(height: 32),
                    if (_error == null) ...[
                      const Text('Opening your space…'),
                      const SizedBox(height: 20),
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ] else ...[
                      Builder(
                        builder: (context) => Text(
                          'Let’s reconnect.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _error is AppFailure
                            ? (_error! as AppFailure).message
                            : 'Check your internet connection and try again.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: mutedInk),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => _open(widget.open),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                      if (widget.connectCloud != null)
                        TextButton(
                          onPressed: () => _open(widget.connectCloud!),
                          child: const Text('Sign in to your account'),
                        ),
                      if (!widget.requireSignIn && widget.openDevice != null)
                        TextButton(
                          onPressed: () => _open(widget.openDevice!),
                          child: const Text('Open device journal'),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
