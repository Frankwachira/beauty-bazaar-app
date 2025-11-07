class Service {
  final String id;
  final String name;
  final int priceKsh;
  final int durationMinutes; // Duration of the service in minutes

  const Service({
    required this.id,
    required this.name,
    required this.priceKsh,
    required this.durationMinutes,
  });
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

  Booking copyWith({
    int? id,
    String? clientName,
    String? phoneNumber,
    String? serviceId,
    String? serviceName,
    int? priceKsh,
    DateTime? appointmentDateTime,
    String? status,
  }) {
    return Booking(
      id: id ?? this.id,
      clientName: clientName ?? this.clientName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      serviceId: serviceId ?? this.serviceId,
      serviceName: serviceName ?? this.serviceName,
      priceKsh: priceKsh ?? this.priceKsh,
      appointmentDateTime: appointmentDateTime ?? this.appointmentDateTime,
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
  // Prices in KSH, durations in minutes
  static const List<Service> all = [
    Service(id: 'gumgell', name: 'Gumgell', priceKsh: 1500, durationMinutes: 120), // 2 hours
    Service(id: 'acrylics', name: 'Acrylics', priceKsh: 2500, durationMinutes: 120), // 2 hours
    Service(id: 'buildergel_tips', name: 'Buildergel + Tips', priceKsh: 1500, durationMinutes: 120), // 2 hours
    Service(id: 'stickons', name: 'Stickons', priceKsh: 1000, durationMinutes: 60), // 1 hour
    Service(id: 'tips', name: 'Tips', priceKsh: 800, durationMinutes: 90), // 1 hour 30 minutes
    Service(id: 'builder', name: 'Builder', priceKsh: 800, durationMinutes: 60), // 1 hour
    Service(id: 'gel_plain', name: 'Gell Plain', priceKsh: 500, durationMinutes: 30), // 30 minutes
    Service(id: 'pedicure_gel', name: 'Pedicure + Gell', priceKsh: 1000, durationMinutes: 90), // 1 hour 30 minutes
    Service(id: 'eyebrow_shaping', name: 'Eyebrow Shaping', priceKsh: 100, durationMinutes: 10), // 10 minutes
    Service(id: 'eyebrow_tinting', name: 'Eyebrow Tinting', priceKsh: 300, durationMinutes: 30), // 30 minutes
    Service(id: 'full_makeup', name: 'Full Make-up', priceKsh: 1000, durationMinutes: 60), // 1 hour
  ];

  /// Get service by ID
  static Service? getById(String id) {
    try {
      return all.firstWhere((s) => s.id == id);
    } catch (e) {
      return null;
    }
  }
}


