import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/src/socket/ssh_socket.dart';

Future<SSHSocket> connectNativeSocket(
  String host,
  int port, {
  Duration? timeout,
}) async {
  final socket = await RawSocket.connect(host, port, timeout: timeout);
  return _SSHNativeSocket._(socket);
}

class _SSHNativeSocket implements SSHSocket {
  final RawSocket _socket;
  final Completer<void> _doneCompleter = Completer();
  final StreamController<Uint8List> _remoteController = StreamController();
  final StreamController<Uint8List> _localController = StreamController(
    sync: true,
  );
  List<int> _writeBuffer = Uint8List(0);

  _SSHNativeSocket._(this._socket) {
    _socket.readEventsEnabled = true;
    _socket.writeEventsEnabled = false;
    _socket.listen((event) {
      if (event == RawSocketEvent.closed ||
          event == RawSocketEvent.readClosed) {
        if (!_doneCompleter.isCompleted) _doneCompleter.complete();
        // _removeSocket(_socket);
      }

      if (event == RawSocketEvent.write) {
        if (_writeBuffer.isEmpty) return;
        final written = _socket.write(_writeBuffer);
        _writeBuffer = _writeBuffer.sublist(written);
        if (_writeBuffer.length != 0) _socket.writeEventsEnabled = true;
      }

      if (event == RawSocketEvent.read) {
        _socket.readEventsEnabled = false;
        final read = _socket.read(1024 * 4);
        if (read != null) _remoteController.add(read);
        Timer(const Duration(milliseconds: 1), () {
          _socket.readEventsEnabled = true;
        });
      }
    });

    _localController.stream.listen((data) {
      _writeBuffer = _writeBuffer + data;
      _socket.writeEventsEnabled = true;
    });

    // _addSocket(_socket, _remoteController.sink);
  }

  @override
  Stream<Uint8List> get stream => _remoteController.stream;

  @override
  StreamSink<List<int>> get sink => _localController;

  @override
  Future<void> close() async {
    await _socket.close();
  }

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  void destroy() {
    _socket.close();
  }

  @override
  String toString() {
    final address = '${_socket.remoteAddress.host}:${_socket.remotePort}';
    return '_SSHNativeSocket($address)';
  }

  // static Timer? _readTimer;
  // static Map<RawSocket, Sink<Uint8List>> _sockets = {};

  // static void _addSocket(RawSocket socket, Sink<Uint8List> sink) {
  //   _sockets[socket] = sink;
  //   _readTimer ??= Timer.periodic(const Duration(milliseconds: 1), (_) {
  //     for (final entry in _sockets.entries) {
  //       final socket = entry.key;
  //       final sink = entry.value;
  //       if (socket.available() > 0) {
  //         final read = socket.read(1024 * 4);
  //         if (read != null) sink.add(read);
  //       }
  //     }
  //   });
  // }

  // static void _removeSocket(RawSocket socket) {
  //   _sockets.remove(socket);
  //   if (_sockets.isEmpty) {
  //     _readTimer?.cancel();
  //     _readTimer = null;
  //   }
  // }
}
