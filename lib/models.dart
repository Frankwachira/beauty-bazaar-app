class Service {
  final String id;
  final String name;
  final int priceKsh;

  const Service({required this.id, required this.name, required this.priceKsh});
}

class Booking {
  final int? id;
  final String clientName;
  final String phoneNumber;
  final String serviceId;
  final String serviceName;
  final int priceKsh;
  final DateTime appointmentDateTime;
  final String status; // 'active' or 'cancelled'

  const Booking({
    this.id,
    required this.clientName,
    required this.phoneNumber,
    required this.serviceId,
    required this.serviceName,
    required this.priceKsh,
    required this.appointmentDateTime,
    this.status = 'active',
  });

  Booking copyWith({int? id, String? status}) {
    return Booking(
      id: id ?? this.id,
      clientName: clientName,
      phoneNumber: phoneNumber,
      serviceId: serviceId,
      serviceName: serviceName,
      priceKsh: priceKsh,
      appointmentDateTime: appointmentDateTime,
      status: status ?? this.status,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'client_name': clientName,
      'phone_number': phoneNumber,
      'service_id': serviceId,
      'service_name': serviceName,
      'price_ksh': priceKsh,
      'appointment_dt': appointmentDateTime.toIso8601String(),
      'status': status,
    };
  }

  static Booking fromMap(Map<String, Object?> map) {
    return Booking(
      id: map['id'] as int?,
      clientName: map['client_name'] as String,
      phoneNumber: map['phone_number'] as String,
      serviceId: map['service_id'] as String,
      serviceName: map['service_name'] as String,
      priceKsh: map['price_ksh'] as int,
      appointmentDateTime: DateTime.parse(map['appointment_dt'] as String),
      status: (map['status'] as String?) ?? 'active',
    );
  }
}

class ServicesCatalog {
  // Prices in KSH
  static const List<Service> all = [
    Service(id: 'gumgell', name: 'Gumgell', priceKsh: 1500),
    Service(id: 'acrylics', name: 'Acrylics', priceKsh: 2500),
    Service(id: 'buildergel_tips', name: 'Buildergel + Tips', priceKsh: 1500),
    Service(id: 'stickons', name: 'Stickons', priceKsh: 1000),
    Service(id: 'tips', name: 'Tips', priceKsh: 800),
    Service(id: 'builder', name: 'Builder', priceKsh: 800),
    Service(id: 'gel_plain', name: 'Gell Plain', priceKsh: 500),
    Service(id: 'pedicure_gel', name: 'Pedicure + Gell', priceKsh: 1000),
    Service(id: 'eyebrow_shaping', name: 'Eyebrow Shaping', priceKsh: 100),
    Service(id: 'eyebrow_tinting', name: 'Eyebrow Tinting', priceKsh: 300),
    Service(id: 'full_makeup', name: 'Full Make-up', priceKsh: 1000),
  ];
}


