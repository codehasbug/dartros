import 'dart:typed_data';

import 'package:buffer/buffer.dart';
import 'package:dartx/dartx.dart';
import 'package:reflectable/reflectable.dart';
import 'msg_utils.dart';

const rosDeserializeCapability = NewInstanceCapability('deserialize');

class RosDeserializeable extends Reflectable {
  const RosDeserializeable() : super(rosDeserializeCapability);
}

const rosDeserializeable = RosDeserializeable();

const callerIdPrefix = 'callerid=';
const md5Prefix = 'md5sum=';
const topicPrefix = 'topic=';
const servicePrefix = 'service=';
const typePrefix = 'type=';
const errorPrefix = 'error=';
const messageDefinitionPrefix = 'message_definition=';
const latchingField = 'latching=1';
const persistentField = 'persistent=1';
const tcpNoDelayField = 'tcp_nodelay=1';

void serializeStringFields(ByteDataWriter writer, List<String> fields) {
  final totalLength = fields.map((f) => f.lenInBytes).sum();
  writer.writeUint32(totalLength, Endian.little);
  fields.forEach((f) => writer.writeString(f));
}

List<String> deserializeStringFields(ByteDataReader reader) {
  final totalLength = reader.readUint32(Endian.little);
  final stringList = <String>[];
  int length = 0;
  while (length < totalLength) {
    final string = reader.readString();
    length += string.lenInBytes;
    stringList.add(string);
  }
  return stringList;
}

void createSubHeader(ByteDataWriter writer, String callerId, String md5sum,
    String topic, String type, String messageDefinition, bool tcpNoDelay) {
  return serializeStringFields(writer, [
    callerIdPrefix + callerId,
    md5Prefix + md5sum,
    topicPrefix + topic,
    typePrefix + type,
    messageDefinitionPrefix + messageDefinition,
    if (tcpNoDelay) tcpNoDelayField
  ]);
}

void createPubHeader(ByteDataWriter writer, String callerId, String md5sum,
    String type, bool latching, String messageDefinition) {
  return serializeStringFields(writer, [
    callerIdPrefix + callerId,
    md5Prefix + md5sum,
    typePrefix + type,
    messageDefinitionPrefix + messageDefinition,
    if (latching) latchingField
  ]);
}

void createServiceClientHeader(ByteDataWriter writer, String callerId,
    String service, String md5sum, String type, bool persistent) {
  return serializeStringFields(writer, [
    callerIdPrefix + callerId,
    servicePrefix + service,
    md5Prefix + md5sum,
    if (persistent) persistentField
  ]);
}

void createServiceServerHeader(
    ByteDataWriter writer, String callerId, String md5sum, String type) {
  return serializeStringFields(writer, [
    callerIdPrefix + callerId,
    md5Prefix + md5sum,
    typePrefix + type,
  ]);
}

Map<String, String> parseTcpRosHeader(header) {
  final info = {};
  final regex = RegExp('^(\w+)=([\s\S]+)');
  final fields = deserializeStringFields(header);
  fields.forEach((field) {
    final hasMatch = regex.hasMatch(field);
    if (!hasMatch) {
      print('Error: Invalid connection header while parsing field $field');
      return;
    }
    final matches = regex.allMatches(field).toList();
    info[matches[0]] = matches[1];
  });
  return info;
}

bool validateSubHeader(ByteDataWriter writer, TCPRosHeader header, String topic,
    String type, String md5sum) {
  if (header.topic.isNullOrEmpty) {
    writer.writeString('Connection header missing expected field [topic]');
    return false;
  }
  if (header.type.isNullOrEmpty) {
    writer.writeString('Connection header missing expected field [type]');
    return false;
  }
  if (header.md5sum.isNullOrEmpty) {
    writer.writeString('Connection header missing expected field [md5sum]');
    return false;
  }
  if (header.topic != topic) {
    writer
        .writeString('Got incorrect topic [${header.topic}] expected [$topic]');
    return false;
  }
  if (header.type != type && header.type != '*') {
    writer.writeString('Got incorrect type [${header.type}] expected [$type]');
    return false;
  }
  if (header.md5sum != md5sum && header.md5sum != '*') {
    writer.writeString(
        'Got incorrect md5sum [${header.md5sum}] expected [$md5sum]');
    return false;
  }
  return true;
}

bool validatePubHeader(
    ByteDataWriter writer, TCPRosHeader header, String type, String md5sum) {
  if (header.type.isNullOrEmpty) {
    writer.writeString('Connection header missing expected field [type]');
    return false;
  }
  if (header.md5sum.isNullOrEmpty) {
    writer.writeString('Connection header missing expected field [md5sum]');
    return false;
  }

  if (header.type != type && header.type != '*') {
    writer.writeString('Got incorrect type [${header.type}] expected [$type]');
    return false;
  }
  if (header.md5sum != md5sum && header.md5sum != '*') {
    writer.writeString(
        'Got incorrect md5sum [${header.md5sum}] expected [$md5sum]');
    return false;
  }
  return true;
}

Uint8List serializeMessage(dynamic message, {prependMessageLength = true}) {
  final msgSize = message.getMessageSize();
  final writer = ByteDataWriter();
  if (prependMessageLength) {
    writer.writeUint32(msgSize);
  }
  message.serialize(writer);
  return writer.toBytes();
}

T deserializeMessage<T>(Uint8List message) {
  final reader = ByteDataReader();
  reader.add(message);
  ClassMirror messageClass = rosDeserializeable.reflectType(T);
  return messageClass.newInstance('deserialize', [reader]);
}

Uint8List serializeResponse(
  dynamic response,
  success, {
  prependResponseInfo = true,
}) {
  final writer = ByteDataWriter();
  if (prependResponseInfo) {
    if (success) {
      final size = response.getMessageSize();
      writer.writeUint8(1);
      writer.writeUint32(size);
      response.serialize(writer);
    } else {
      const errorMessage = 'Unable to handle service call';
      writer.writeUint8(0);
      writer.writeString(errorMessage);
    }
  }
  return writer.toBytes();
}

void createTcpRosError(ByteDataWriter writer, String str) {
  writer.writeString(str);
}

class TCPRosHeader<T> {
  final String topic;
  final String type;
  final String md5sum;

  const TCPRosHeader(this.topic, this.type, this.md5sum);
}