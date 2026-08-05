/// mDNS service type used for the Peadra sync layer.
const String syncServiceType = '_peadra-sync._tcp';

/// A Peadra device discovered on the local network via mDNS.
class DiscoveredService {
  const DiscoveredService({
    required this.nodeId,
    required this.deviceName,
    required this.protocolVersion,
    required this.host,
    required this.port,
  });

  final String nodeId;
  final String deviceName;
  final int protocolVersion;
  final String host;
  final int port;

  @override
  bool operator ==(Object other) {
    return other is DiscoveredService &&
        other.nodeId == nodeId &&
        other.deviceName == deviceName &&
        other.protocolVersion == protocolVersion &&
        other.host == host &&
        other.port == port;
  }

  @override
  int get hashCode => Object.hash(nodeId, deviceName, protocolVersion, host, port);

  @override
  String toString() =>
      'DiscoveredService($deviceName@$host:$port, node=$nodeId, proto=$protocolVersion)';
}
