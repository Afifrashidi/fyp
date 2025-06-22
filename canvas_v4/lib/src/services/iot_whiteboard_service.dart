// // lib/src/services/iot_whiteboard_service.dart
// import 'dart:async';
// import 'dart:convert';
// import 'dart:typed_data';
// import 'package:flutter/material.dart';
// import 'package:web_socket_channel/web_socket_channel.dart';
// import 'package:mqtt_client/mqtt_client.dart';
// import 'package:mqtt_client/mqtt_server_client.dart';
//
// // Service for handling IoT whiteboard integration
// class IoTWhiteboardService {
//   // WebSocket for real-time data
//   WebSocketChannel? _webSocketChannel;
//
//   // MQTT client for IoT communication
//   MqttServerClient? _mqttClient;
//
//   // Stream controllers
//   final _gestureDataController = StreamController<GestureData>.broadcast();
//   final _handwritingDataController = StreamController<HandwritingData>.broadcast();
//   final _rawSensorDataController = StreamController<RawSensorData>.broadcast();
//   final _connectionStateController = StreamController<IoTConnectionState>.broadcast();
//
//   // Streams
//   Stream<GestureData> get gestureStream => _gestureDataController.stream;
//   Stream<HandwritingData> get handwritingStream => _handwritingDataController.stream;
//   Stream<RawSensorData> get rawSensorStream => _rawSensorDataController.stream;
//   Stream<IoTConnectionState> get connectionStateStream => _connectionStateController.stream;
//
//   // Current state
//   IoTConnectionState _connectionState = IoTConnectionState.disconnected;
//   String? _deviceId;
//
//   // Calibration data
//   CalibrationData? _calibration;
//
//   // Connect to IoT whiteboard via WebSocket
//   Future<void> connectWebSocket({
//     required String serverUrl,
//     required String deviceId,
//   }) async {
//     try {
//       _deviceId = deviceId;
//       _updateConnectionState(IoTConnectionState.connecting);
//
//       _webSocketChannel = WebSocketChannel.connect(
//         Uri.parse('ws://$serverUrl/whiteboard/$deviceId'),
//       );
//
//       _webSocketChannel!.stream.listen(
//         _handleWebSocketData,
//         onError: (error) {
//           print('WebSocket error: $error');
//           _updateConnectionState(IoTConnectionState.error);
//         },
//         onDone: () {
//           _updateConnectionState(IoTConnectionState.disconnected);
//         },
//       );
//
//       // Send handshake
//       _webSocketChannel!.sink.add(jsonEncode({
//         'type': 'handshake',
//         'device_id': deviceId,
//         'timestamp': DateTime.now().toIso8601String(),
//       }));
//
//       _updateConnectionState(IoTConnectionState.connected);
//     } catch (e) {
//       print('Failed to connect WebSocket: $e');
//       _updateConnectionState(IoTConnectionState.error);
//     }
//   }
//
//   // Connect to IoT whiteboard via MQTT
//   Future<void> connectMQTT({
//     required String brokerUrl,
//     required int port,
//     required String deviceId,
//     String? username,
//     String? password,
//   }) async {
//     try {
//       _deviceId = deviceId;
//       _updateConnectionState(IoTConnectionState.connecting);
//
//       _mqttClient = MqttServerClient(brokerUrl, deviceId);
//       _mqttClient!.port = port;
//       _mqttClient!.logging(on: false);
//       _mqttClient!.keepAlivePeriod = 60;
//       _mqttClient!.onConnected = _onMQTTConnected;
//       _mqttClient!.onDisconnected = _onMQTTDisconnected;
//       _mqttClient!.onSubscribed = _onMQTTSubscribed;
//
//       final connMessage = MqttConnectMessage()
//           .clientIdentifier(deviceId)
//           .withWillTopic('whiteboard/$deviceId/status')
//           .withWillMessage('offline')
//           .startClean()
//           .withWillQos(MqttQos.atLeastOnce);
//
//       if (username != null && password != null) {
//         connMessage.authenticateAs(username, password);
//       }
//
//       _mqttClient!.connectionMessage = connMessage;
//
//       await _mqttClient!.connect();
//
//       // Subscribe to device topics
//       _mqttClient!.subscribe('whiteboard/$deviceId/gesture', MqttQos.atLeastOnce);
//       _mqttClient!.subscribe('whiteboard/$deviceId/handwriting', MqttQos.atLeastOnce);
//       _mqttClient!.subscribe('whiteboard/$deviceId/sensors', MqttQos.atLeastOnce);
//
//       _mqttClient!.updates!.listen(_handleMQTTMessage);
//
//     } catch (e) {
//       print('Failed to connect MQTT: $e');
//       _updateConnectionState(IoTConnectionState.error);
//     }
//   }
//
//   // Process WebSocket data
//   void _handleWebSocketData(dynamic data) {
//     try {
//       final Map<String, dynamic> message = jsonDecode(data);
//       final type = message['type'] as String;
//
//       switch (type) {
//         case 'gesture':
//           _processGestureData(message['data']);
//           break;
//         case 'handwriting':
//           _processHandwritingData(message['data']);
//           break;
//         case 'sensors':
//           _processRawSensorData(message['data']);
//           break;
//         case 'calibration':
//           _processCalibrationData(message['data']);
//           break;
//       }
//     } catch (e) {
//       print('Error processing WebSocket data: $e');
//     }
//   }
//
//   // Process MQTT messages
//   void _handleMQTTMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
//     for (final message in messages) {
//       final topic = message.topic;
//       final payload = message.payload as MqttPublishMessage;
//       final data = MqttPublishPayload.bytesToStringAsString(payload.payload.message);
//
//       try {
//         final jsonData = jsonDecode(data);
//
//         if (topic.endsWith('/gesture')) {
//           _processGestureData(jsonData);
//         } else if (topic.endsWith('/handwriting')) {
//           _processHandwritingData(jsonData);
//         } else if (topic.endsWith('/sensors')) {
//           _processRawSensorData(jsonData);
//         }
//       } catch (e) {
//         print('Error processing MQTT message: $e');
//       }
//     }
//   }
//
//   // Process gesture data from IoT device
//   void _processGestureData(Map<String, dynamic> data) {
//     final gesture = GestureData(
//       type: GestureType.values.firstWhere(
//             (g) => g.toString().split('.').last == data['gesture_type'],
//         orElse: () => GestureType.unknown,
//       ),
//       startPoint: Offset(data['start_x'].toDouble(), data['start_y'].toDouble()),
//       endPoint: Offset(data['end_x'].toDouble(), data['end_y'].toDouble()),
//       velocity: data['velocity']?.toDouble() ?? 0.0,
//       pressure: data['pressure']?.toDouble() ?? 1.0,
//       timestamp: DateTime.parse(data['timestamp']),
//     );
//
//     // Apply calibration if available
//     if (_calibration != null) {
//       gesture.startPoint = _applyCalibration(gesture.startPoint);
//       gesture.endPoint = _applyCalibration(gesture.endPoint);
//     }
//
//     _gestureDataController.add(gesture);
//   }
//
//   // Process handwriting data
//   void _processHandwritingData(Map<String, dynamic> data) {
//     final points = (data['points'] as List).map((p) =>
//         StrokePoint(
//           x: p['x'].toDouble(),
//           y: p['y'].toDouble(),
//           pressure: p['pressure']?.toDouble() ?? 1.0,
//           timestamp: p['timestamp'] != null ? DateTime.parse(p['timestamp']) : DateTime.now(),
//         )
//     ).toList();
//
//     // Apply calibration to points
//     if (_calibration != null) {
//       for (var point in points) {
//         final calibrated = _applyCalibration(Offset(point.x, point.y));
//         point.x = calibrated.dx;
//         point.y = calibrated.dy;
//       }
//     }
//
//     final handwriting = HandwritingData(
//       strokeId: data['stroke_id'],
//       points: points,
//       color: data['color'] != null ? Color(data['color']) : Colors.black,
//       thickness: data['thickness']?.toDouble() ?? 2.0,
//       timestamp: DateTime.parse(data['timestamp']),
//     );
//
//     _handwritingDataController.add(handwriting);
//   }
//
//   // Process raw sensor data
//   void _processRawSensorData(Map<String, dynamic> data) {
//     final sensorData = RawSensorData(
//       accelerometer: Vector3(
//         data['accel_x']?.toDouble() ?? 0,
//         data['accel_y']?.toDouble() ?? 0,
//         data['accel_z']?.toDouble() ?? 0,
//       ),
//       gyroscope: Vector3(
//         data['gyro_x']?.toDouble() ?? 0,
//         data['gyro_y']?.toDouble() ?? 0,
//         data['gyro_z']?.toDouble() ?? 0,
//       ),
//       magnetometer: Vector3(
//         data['mag_x']?.toDouble() ?? 0,
//         data['mag_y']?.toDouble() ?? 0,
//         data['mag_z']?.toDouble() ?? 0,
//       ),
//       pressure: data['pressure']?.toDouble() ?? 0,
//       proximity: data['proximity']?.toDouble() ?? 0,
//       timestamp: DateTime.parse(data['timestamp']),
//     );
//
//     _rawSensorDataController.add(sensorData);
//   }
//
//   // Process calibration data
//   void _processCalibrationData(Map<String, dynamic> data) {
//     _calibration = CalibrationData(
//       topLeft: Offset(data['top_left_x'].toDouble(), data['top_left_y'].toDouble()),
//       topRight: Offset(data['top_right_x'].toDouble(), data['top_right_y'].toDouble()),
//       bottomLeft: Offset(data['bottom_left_x'].toDouble(), data['bottom_left_y'].toDouble()),
//       bottomRight: Offset(data['bottom_right_x'].toDouble(), data['bottom_right_y'].toDouble()),
//       canvasWidth: data['canvas_width'].toDouble(),
//       canvasHeight: data['canvas_height'].toDouble(),
//     );
//   }
//
//   // Apply calibration transformation
//   Offset _applyCalibration(Offset raw) {
//     if (_calibration == null) return raw;
//
//     // Simple bilinear interpolation for calibration
//     // This is a simplified version - real implementation would be more complex
//     final cal = _calibration!;
//
//     // Normalize to 0-1 range
//     final normalizedX = raw.dx / cal.canvasWidth;
//     final normalizedY = raw.dy / cal.canvasHeight;
//
//     // Bilinear interpolation
//     final top = Offset.lerp(cal.topLeft, cal.topRight, normalizedX)!;
//     final bottom = Offset.lerp(cal.bottomLeft, cal.bottomRight, normalizedX)!;
//     final calibrated = Offset.lerp(top, bottom, normalizedY)!;
//
//     return calibrated;
//   }
//
//   // Start calibration process
//   Future<void> startCalibration() async {
//     if (_webSocketChannel != null) {
//       _webSocketChannel!.sink.add(jsonEncode({
//         'type': 'command',
//         'command': 'start_calibration',
//         'timestamp': DateTime.now().toIso8601String(),
//       }));
//     }
//
//     if (_mqttClient != null && _deviceId != null) {
//       final builder = MqttClientPayloadBuilder();
//       builder.addString(jsonEncode({
//         'command': 'start_calibration',
//         'timestamp': DateTime.now().toIso8601String(),
//       }));
//       _mqttClient!.publishMessage(
//         'whiteboard/$_deviceId/command',
//         MqttQos.atLeastOnce,
//         builder.payload!,
//       );
//     }
//   }
//
//   // Send command to IoT device
//   Future<void> sendCommand(String command, Map<String, dynamic>? parameters) async {
//     final message = {
//       'type': 'command',
//       'command': command,
//       'parameters': parameters,
//       'timestamp': DateTime.now().toIso8601String(),
//     };
//
//     if (_webSocketChannel != null) {
//       _webSocketChannel!.sink.add(jsonEncode(message));
//     }
//
//     if (_mqttClient != null && _deviceId != null) {
//       final builder = MqttClientPayloadBuilder();
//       builder.addString(jsonEncode(message));
//       _mqttClient!.publishMessage(
//         'whiteboard/$_deviceId/command',
//         MqttQos.atLeastOnce,
//         builder.payload!,
//       );
//     }
//   }
//
//   // Update connection state
//   void _updateConnectionState(IoTConnectionState state) {
//     _connectionState = state;
//     _connectionStateController.add(state);
//   }
//
//   // MQTT callbacks
//   void _onMQTTConnected() {
//     _updateConnectionState(IoTConnectionState.connected);
//     print('MQTT Connected');
//   }
//
//   void _onMQTTDisconnected() {
//     _updateConnectionState(IoTConnectionState.disconnected);
//     print('MQTT Disconnected');
//   }
//
//   void _onMQTTSubscribed(String topic) {
//     print('MQTT Subscribed to: $topic');
//   }
//
//   // Disconnect from IoT device
//   Future<void> disconnect() async {
//     if (_webSocketChannel != null) {
//       await _webSocketChannel!.sink.close();
//       _webSocketChannel = null;
//     }
//
//     if (_mqttClient != null) {
//       _mqttClient!.disconnect();
//       _mqttClient = null;
//     }
//
//     _updateConnectionState(IoTConnectionState.disconnected);
//   }
//
//   void dispose() {
//     disconnect();
//     _gestureDataController.close();
//     _handwritingDataController.close();
//     _rawSensorDataController.close();
//     _connectionStateController.close();
//   }
// }
//
// // Data models
// enum IoTConnectionState {
//   disconnected,
//   connecting,
//   connected,
//   error,
// }
//
// enum GestureType {
//   tap,
//   doubleTap,
//   longPress,
//   swipeLeft,
//   swipeRight,
//   swipeUp,
//   swipeDown,
//   pinch,
//   zoom,
//   rotate,
//   erase,
//   unknown,
// }
//
// class GestureData {
//   final GestureType type;
//   Offset startPoint;
//   Offset endPoint;
//   final double velocity;
//   final double pressure;
//   final DateTime timestamp;
//
//   GestureData({
//     required this.type,
//     required this.startPoint,
//     required this.endPoint,
//     required this.velocity,
//     required this.pressure,
//     required this.timestamp,
//   });
// }
//
// class StrokePoint {
//   double x;
//   double y;
//   final double pressure;
//   final DateTime timestamp;
//
//   StrokePoint({
//     required this.x,
//     required this.y,
//     required this.pressure,
//     required this.timestamp,
//   });
// }
//
// class HandwritingData {
//   final String strokeId;
//   final List<StrokePoint> points;
//   final Color color;
//   final double thickness;
//   final DateTime timestamp;
//
//   HandwritingData({
//     required this.strokeId,
//     required this.points,
//     required this.color,
//     required this.thickness,
//     required this.timestamp,
//   });
// }
//
// class Vector3 {
//   final double x;
//   final double y;
//   final double z;
//
//   Vector3(this.x, this.y, this.z);
// }
//
// class RawSensorData {
//   final Vector3 accelerometer;
//   final Vector3 gyroscope;
//   final Vector3 magnetometer;
//   final double pressure;
//   final double proximity;
//   final DateTime timestamp;
//
//   RawSensorData({
//     required this.accelerometer,
//     required this.gyroscope,
//     required this.magnetometer,
//     required this.pressure,
//     required this.proximity,
//     required this.timestamp,
//   });
// }
//
// class CalibrationData {
//   final Offset topLeft;
//   final Offset topRight;
//   final Offset bottomLeft;
//   final Offset bottomRight;
//   final double canvasWidth;
//   final double canvasHeight;
//
//   CalibrationData({
//     required this.topLeft,
//     required this.topRight,
//     required this.bottomLeft,
//     required this.bottomRight,
//     required this.canvasWidth,
//     required this.canvasHeight,
//   });
// }