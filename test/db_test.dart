import 'package:flutter_test/flutter_test.dart';
import 'package:beautybazaarapp/db.dart';
import 'package:beautybazaarapp/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // Initialize FFI for testing
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('AppDatabase Tests', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase();
      // Clear any existing data by creating a fresh instance
      // In a real scenario, you might want to use an in-memory database
    });

    tearDown(() async {
      // Clean up after each test
      try {
        final database = await db.database;
        await database.delete('bookings');
        await database.delete('users');
      } catch (e) {
        // Ignore errors during cleanup
      }
    });

    test('insertBooking should create a new booking', () async {
      // Arrange
      final booking = Booking(
        clientName: 'Test User',
        phoneNumber: '254712345678',
        serviceId: 'gumgell',
        serviceName: 'Gumgell',
        priceKsh: 1500,
        appointmentDateTime: DateTime.now().add(const Duration(days: 1)),
      );

      // Act
      final result = await db.insertBooking(booking);

      // Assert
      expect(result.id, isNotNull);
      expect(result.clientName, equals('Test User'));
      expect(result.phoneNumber, equals('254712345678'));
      expect(result.status, equals('active'));
    });

    test('getAllBookings should return all bookings', () async {
      // Arrange
      final booking1 = Booking(
        clientName: 'User 1',
        phoneNumber: '254712345678',
        serviceId: 'gumgell',
        serviceName: 'Gumgell',
        priceKsh: 1500,
        appointmentDateTime: DateTime.now().add(const Duration(days: 1)),
      );
      final booking2 = Booking(
        clientName: 'User 2',
        phoneNumber: '254712345679',
        serviceId: 'acrylics',
        serviceName: 'Acrylics',
        priceKsh: 2500,
        appointmentDateTime: DateTime.now().add(const Duration(days: 2)),
      );

      await db.insertBooking(booking1);
      await db.insertBooking(booking2);

      // Act
      final bookings = await db.getAllBookings();

      // Assert
      expect(bookings.length, greaterThanOrEqualTo(2));
      expect(bookings.any((b) => b.clientName == 'User 1'), isTrue);
      expect(bookings.any((b) => b.clientName == 'User 2'), isTrue);
    });

    test('getMonthlyRevenueKsh should calculate revenue correctly', () async {
      // Arrange
      final now = DateTime.now();
      final booking1 = Booking(
        clientName: 'User 1',
        phoneNumber: '254712345678',
        serviceId: 'gumgell',
        serviceName: 'Gumgell',
        priceKsh: 1500,
        appointmentDateTime: DateTime(now.year, now.month, 15),
      );
      final booking2 = Booking(
        clientName: 'User 2',
        phoneNumber: '254712345679',
        serviceId: 'acrylics',
        serviceName: 'Acrylics',
        priceKsh: 2500,
        appointmentDateTime: DateTime(now.year, now.month, 20),
      );

      await db.insertBooking(booking1);
      await db.insertBooking(booking2);

      // Act
      final revenue = await db.getMonthlyRevenueKsh(now.year, now.month);

      // Assert
      expect(revenue, greaterThanOrEqualTo(4000)); // 1500 + 2500
    });

    test('getMonthlyRevenueKsh should exclude cancelled bookings', () async {
      // Arrange
      final now = DateTime.now();
      final booking1 = Booking(
        clientName: 'User 1',
        phoneNumber: '254712345678',
        serviceId: 'gumgell',
        serviceName: 'Gumgell',
        priceKsh: 1500,
        appointmentDateTime: DateTime(now.year, now.month, 15),
      );
      final booking2 = Booking(
        clientName: 'User 2',
        phoneNumber: '254712345679',
        serviceId: 'acrylics',
        serviceName: 'Acrylics',
        priceKsh: 2500,
        appointmentDateTime: DateTime(now.year, now.month, 20),
      );

      final inserted1 = await db.insertBooking(booking1);
      final inserted2 = await db.insertBooking(booking2);

      // Cancel one booking
      if (inserted1.id != null) {
        await db.cancelBooking(inserted1.id!);
      }

      // Act
      final revenue = await db.getMonthlyRevenueKsh(now.year, now.month);

      // Assert
      expect(revenue, greaterThanOrEqualTo(2500)); // Only booking2
      expect(revenue, lessThan(4000)); // Less than both combined
    });

    test('cancelBooking should update booking status', () async {
      // Arrange
      final booking = Booking(
        clientName: 'Test User',
        phoneNumber: '254712345678',
        serviceId: 'gumgell',
        serviceName: 'Gumgell',
        priceKsh: 1500,
        appointmentDateTime: DateTime.now().add(const Duration(days: 1)),
      );

      final inserted = await db.insertBooking(booking);
      expect(inserted.id, isNotNull);

      // Act
      await db.cancelBooking(inserted.id!);

      // Assert
      final bookings = await db.getAllBookings();
      final cancelledBooking = bookings.firstWhere((b) => b.id == inserted.id);
      expect(cancelledBooking.status, equals('cancelled'));
    });

    test('cancelBooking should throw error for non-existent booking', () async {
      // Act & Assert
      expect(() => db.cancelBooking(99999), throwsA(isA<Exception>()));
    });

    test('createUser should create a new user', () async {
      // Act
      await db.createUser('testuser', 'password123');

      // Assert
      final exists = await db.usernameExists('testuser');
      expect(exists, isTrue);
    });

    test('createUser should throw error for duplicate username', () async {
      // Arrange
      await db.createUser('testuser', 'password123');

      // Act & Assert
      expect(
        () => db.createUser('testuser', 'password456'),
        throwsA(isA<Exception>()),
      );
    });

    test('validateLogin should return true for correct credentials', () async {
      // Arrange
      await db.createUser('testuser', 'password123');

      // Act
      final isValid = await db.validateLogin('testuser', 'password123');

      // Assert
      expect(isValid, isTrue);
    });

    test('validateLogin should return false for incorrect password', () async {
      // Arrange
      await db.createUser('testuser', 'password123');

      // Act
      final isValid = await db.validateLogin('testuser', 'wrongpassword');

      // Assert
      expect(isValid, isFalse);
    });

    test('validateLogin should return false for non-existent user', () async {
      // Act
      final isValid = await db.validateLogin('nonexistent', 'password123');

      // Assert
      expect(isValid, isFalse);
    });

    test('usernameExists should return true for existing user', () async {
      // Arrange
      await db.createUser('testuser', 'password123');

      // Act
      final exists = await db.usernameExists('testuser');

      // Assert
      expect(exists, isTrue);
    });

    test('usernameExists should return false for non-existent user', () async {
      // Act
      final exists = await db.usernameExists('nonexistent');

      // Assert
      expect(exists, isFalse);
    });

    test(
      'findBookingsByPhone should return bookings for matching phone',
      () async {
        // Arrange
        final phone = '254712345678';
        final booking1 = Booking(
          clientName: 'User 1',
          phoneNumber: phone,
          serviceId: 'gumgell',
          serviceName: 'Gumgell',
          priceKsh: 1500,
          appointmentDateTime: DateTime.now().add(const Duration(days: 1)),
        );
        final booking2 = Booking(
          clientName: 'User 2',
          phoneNumber: phone,
          serviceId: 'acrylics',
          serviceName: 'Acrylics',
          priceKsh: 2500,
          appointmentDateTime: DateTime.now().add(const Duration(days: 2)),
        );
        final booking3 = Booking(
          clientName: 'User 3',
          phoneNumber: '254712345679',
          serviceId: 'stickons',
          serviceName: 'Stickons',
          priceKsh: 1000,
          appointmentDateTime: DateTime.now().add(const Duration(days: 3)),
        );

        await db.insertBooking(booking1);
        await db.insertBooking(booking2);
        await db.insertBooking(booking3);

        // Act
        final bookings = await db.findBookingsByPhone(phone);

        // Assert
        expect(bookings.length, greaterThanOrEqualTo(2));
        expect(bookings.every((b) => b.phoneNumber == phone), isTrue);
      },
    );

    test('getUserRole should return role for existing user', () async {
      // Arrange
      await db.createUser('testuser', 'password123');

      // Act
      final role = await db.getUserRole('testuser');

      // Assert
      expect(role, isNotNull);
      expect(role, isA<String>());
    });

    test('getUserRole should return null for non-existent user', () async {
      // Act
      final role = await db.getUserRole('nonexistent');

      // Assert
      expect(role, isNull);
    });
  });
}
