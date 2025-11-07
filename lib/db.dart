import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart'
    show Database, openDatabase, getDatabasesPath;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'models.dart';
import 'utils.dart';

class AppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;
  AppDatabase._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _openDb();
    return _db!;
  }

  Future<Database> _openDb() async {
    // Ensure a database factory exists on every platform
    try {
      if (kIsWeb) {
        databaseFactory = databaseFactoryFfiWeb;
        AppLogger.debug('Using web database factory');
      } else {
        // Try to get databases path - this will fail on desktop if factory isn't set
        try {
          await getDatabasesPath();
          AppLogger.debug('Database path obtained successfully');
        } catch (e) {
          AppLogger.debug('Failed to get database path, trying FFI: $e');
          // On desktop platforms, we need to initialize FFI
          try {
            sqfliteFfiInit();
            databaseFactory = databaseFactoryFfi;
            AppLogger.debug('FFI initialized successfully');
          } catch (e2) {
            AppLogger.warning('FFI init failed: $e2');
            // FFI init failed, will use default sqflite
          }
        }
      }
    } catch (e) {
      AppLogger.error('Error in database factory setup', e, null, 'AppDatabase');
      // If all else fails, try to initialize FFI for desktop
      if (!kIsWeb) {
        try {
          sqfliteFfiInit();
          databaseFactory = databaseFactoryFfi;
          AppLogger.debug('FFI initialized in fallback');
        } catch (e2) {
          AppLogger.warning('FFI init failed in fallback: $e2');
          // If this fails, will use default sqflite (mobile platform)
        }
      }
    }

    // Try to use factory if available, otherwise use default sqflite
    try {
      final factory = databaseFactory;
      if (factory != null) {
        // Use factory for desktop/web platforms
        final path = kIsWeb
            ? 'beautybazaar.db'
            : p.join(await getDatabasesPath(), 'beautybazaar.db');
        final db = await factory.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 4,
            onCreate: _onCreate,
            onUpgrade: _onUpgrade,
          ),
        );
        // Defensive: ensure tables exist even if versioning was skipped
        await _ensureSchema(db);
        return db;
      }
    } catch (_) {
      // Factory usage failed, fall through to default sqflite
    }

    // On mobile platforms, use default sqflite (no factory needed)
    final path = p.join(await getDatabasesPath(), 'beautybazaar.db');
    final db = await openDatabase(
      path,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    // Defensive: ensure tables exist even if versioning was skipped
    await _ensureSchema(db);
    return db;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE bookings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_name TEXT NOT NULL,
        phone_number TEXT NOT NULL,
        service_id TEXT NOT NULL,
        service_name TEXT NOT NULL,
        price_ksh INTEGER NOT NULL,
        appointment_dt TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active'
      );
    ''');
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        created_at TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'viewer'
      );
    ''');
    await db.execute('''
      CREATE TABLE services (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        price_ksh INTEGER NOT NULL,
        duration_minutes INTEGER NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      );
    ''');
    await _ensureSchema(db);
    await _initializeDefaultServices(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          username TEXT NOT NULL UNIQUE,
          password_hash TEXT NOT NULL,
          salt TEXT NOT NULL,
          created_at TEXT NOT NULL,
          role TEXT NOT NULL DEFAULT 'viewer'
        );
      ''');
    }
    if (oldVersion < 3) {
      // Add status column to bookings
      try {
        await db.execute(
          "ALTER TABLE bookings ADD COLUMN status TEXT NOT NULL DEFAULT 'active'",
        );
      } catch (_) {}
      // Add role to users
      try {
        await db.execute(
          "ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'viewer'",
        );
      } catch (_) {}
    }
    if (oldVersion < 4) {
      // Add services table
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS services (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            price_ksh INTEGER NOT NULL,
            duration_minutes INTEGER NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1
          );
        ''');
        await _initializeDefaultServices(db);
      } catch (_) {}
    }
    await _ensureSchema(db);
  }

  Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS bookings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_name TEXT NOT NULL,
        phone_number TEXT NOT NULL,
        service_id TEXT NOT NULL,
        service_name TEXT NOT NULL,
        price_ksh INTEGER NOT NULL,
        appointment_dt TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active'
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        created_at TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'viewer'
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS services (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        price_ksh INTEGER NOT NULL,
        duration_minutes INTEGER NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      );
    ''');
    await _ensureOwnerExists(db);
    await _initializeDefaultServices(db);
  }

  Future<void> _initializeDefaultServices(Database db) async {
    try {
      // Check if services already exist
      final existingServices = await db.rawQuery('SELECT COUNT(*) as count FROM services');
      final count = (existingServices.first['count'] as int?) ?? 0;
      
      if (count == 0) {
        // Insert default services from ServicesCatalog
        for (final service in ServicesCatalog.all) {
          await db.insert('services', {
            'id': service.id,
            'name': service.name,
            'price_ksh': service.priceKsh,
            'duration_minutes': service.durationMinutes,
            'is_active': 1,
          });
        }
        AppLogger.info('Default services initialized');
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error initializing default services', e, stackTrace, 'AppDatabase');
    }
  }

  Future<void> _ensureOwnerExists(Database db) async {
    final owners = await db.rawQuery(
      "SELECT COUNT(*) as c FROM users WHERE role = 'owner'",
    );
    final ownersCount = (owners.first['c'] as int?) ?? 0;
    if (ownersCount == 0) {
      final firstUser = await db.query(
        'users',
        orderBy: 'created_at ASC',
        limit: 1,
        columns: ['id'],
      );
      if (firstUser.isNotEmpty) {
        final id = firstUser.first['id'] as int;
        await db.update(
          'users',
          {'role': 'owner'},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
  }

  Future<Booking> insertBooking(Booking booking) async {
    try {
      AppLogger.debug('Inserting booking: ${booking.serviceName}');
      final db = await database;
      final newId = await db.insert('bookings', booking.toMap());
      AppLogger.info('Booking inserted with ID: $newId');
      return booking.copyWith(id: newId);
    } catch (e, stackTrace) {
      AppLogger.error('Error inserting booking', e, stackTrace, 'AppDatabase');
      rethrow;
    }
  }

  Future<List<Booking>> getAllBookings() async {
    final db = await database;
    final rows = await db.query('bookings', orderBy: 'appointment_dt DESC');
    return rows.map((m) => Booking.fromMap(m)).toList();
  }

  Future<int> getMonthlyRevenueKsh(int year, int month) async {
    final db = await database;
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);
    final rows = await db.rawQuery(
      "SELECT SUM(price_ksh) as total FROM bookings WHERE status = 'active' AND appointment_dt >= ? AND appointment_dt < ?",
      [start.toIso8601String(), end.toIso8601String()],
    );
    final total = rows.first['total'] as int?;
    return total ?? 0;
  }

  // ---- AUTH HELPERS ----
  String _generateSalt({int length = 16}) {
    final rand = Random.secure();
    final bytes = List<int>.generate(length, (_) => rand.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hashPassword(String password, String salt) {
    final bytes = utf8.encode('$salt:$password');
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<bool> usernameExists(String username) async {
    final db = await database;
    final rows = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Check if any users exist in the database
  Future<bool> hasAnyUsers() async {
    try {
      AppLogger.debug('Checking if any users exist');
      final db = await database;
      final rows = await db.rawQuery('SELECT COUNT(*) as count FROM users');
      final count = (rows.first['count'] as int?) ?? 0;
      AppLogger.debug('User count: $count');
      return count > 0;
    } catch (e, stackTrace) {
      AppLogger.error('Error checking if users exist', e, stackTrace, 'AppDatabase');
      // Return false on error to show setup screen
      return false;
    }
  }

  Future<void> createUser(String username, String password) async {
    try {
      AppLogger.debug('Creating user: $username');
      final db = await database;
      
      // Validate inputs
      final trimmedUsername = username.trim();
      if (trimmedUsername.isEmpty) {
        throw Exception('Username cannot be empty');
      }
      if (password.isEmpty) {
        throw Exception('Password cannot be empty');
      }
      if (trimmedUsername.length < 3) {
        throw Exception('Username must be at least 3 characters');
      }
      if (password.length < 4) {
        throw Exception('Password must be at least 4 characters');
      }
      
      // Check if username already exists
      final exists = await usernameExists(trimmedUsername);
      if (exists) {
        AppLogger.warning('Username already exists: $trimmedUsername');
        throw Exception('Username already exists. Please choose a different username.');
      }
      
      // First user becomes 'owner', others 'viewer'
      final ownersRows = await db.rawQuery(
        "SELECT COUNT(*) as c FROM users WHERE role = 'owner'",
      );
      final ownersCount = (ownersRows.first['c'] as int?) ?? 0;
      final role = ownersCount == 0 ? 'owner' : 'viewer';
      
      AppLogger.debug('Creating user with role: $role');
      
      // Generate salt and hash password
      final salt = _generateSalt();
      final hash = _hashPassword(password, salt);
      
      AppLogger.debug('Salt generated, hash created');
      
      // Insert user into database
      final userId = await db.insert('users', {
        'username': trimmedUsername,
        'password_hash': hash,
        'salt': salt,
        'created_at': DateTime.now().toIso8601String(),
        'role': role,
      });
      
      AppLogger.info('User created successfully with ID: $userId');
      
      // Verify the user was created
      final verifyExists = await usernameExists(trimmedUsername);
      if (!verifyExists) {
        throw Exception('User creation verification failed');
      }
      
      AppLogger.info('User creation verified successfully');
    } catch (e, stackTrace) {
      AppLogger.error('Error creating user: ${e.toString()}', e, stackTrace, 'AppDatabase');
      rethrow;
    }
  }

  Future<bool> validateLogin(String username, String password) async {
    try {
      AppLogger.debug('Validating login for: $username');
      final db = await database;
      
      final rows = await db.query(
        'users',
        where: 'username = ?',
        whereArgs: [username.trim()],
        limit: 1,
      );
      
      if (rows.isEmpty) {
        AppLogger.debug('User not found: $username');
        return false;
      }
      
      final salt = rows.first['salt'] as String?;
      final expected = rows.first['password_hash'] as String?;
      
      if (salt == null || expected == null) {
        AppLogger.error('Invalid user data: missing salt or hash');
        return false;
      }
      
      final provided = _hashPassword(password, salt);
      final isValid = provided == expected;
      
      AppLogger.debug('Login validation result: $isValid');
      return isValid;
    } catch (e, stackTrace) {
      AppLogger.error('Error validating login', e, stackTrace, 'AppDatabase');
      return false;
    }
  }

  Future<String?> getUserRole(String username) async {
    final db = await database;
    final rows = await db.query(
      'users',
      columns: ['role'],
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['role'] as String;
  }

  Future<void> cancelBooking(int id) async {
    try {
      AppLogger.debug('Cancelling booking ID: $id');
      final db = await database;
      final rowsAffected = await db.update(
        'bookings',
        {'status': 'cancelled'},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rowsAffected == 0) {
        AppLogger.warning('No booking found with ID: $id');
        throw Exception('Booking not found');
      }
      AppLogger.info('Booking cancelled successfully: $id');
    } catch (e, stackTrace) {
      AppLogger.error('Error cancelling booking', e, stackTrace, 'AppDatabase');
      rethrow;
    }
  }

  Future<List<Booking>> findBookingsByPhone(String phone) async {
    final db = await database;
    final rows = await db.query(
      'bookings',
      where: 'phone_number = ?',
      whereArgs: [phone],
      orderBy: 'appointment_dt DESC',
    );
    return rows.map((m) => Booking.fromMap(m)).toList();
  }

  /// Get all active bookings for a specific date
  Future<List<Booking>> getBookingsForDate(DateTime date) async {
    final db = await database;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final rows = await db.rawQuery(
      "SELECT * FROM bookings WHERE status = 'active' AND appointment_dt >= ? AND appointment_dt < ? ORDER BY appointment_dt ASC",
      [startOfDay.toIso8601String(), endOfDay.toIso8601String()],
    );
    return rows.map((m) => Booking.fromMap(m)).toList();
  }

  /// Check if there's a booking conflict for a given time slot
  /// Returns true if there's a conflict, false otherwise
  Future<bool> hasBookingConflict(
    DateTime startTime,
    int durationMinutes,
  ) async {
    try {
      final endTime = startTime.add(Duration(minutes: durationMinutes));
      
      // Get all active bookings for the same day
      final bookings = await getBookingsForDate(startTime);
      
      // Check if any booking overlaps with the requested time slot
      for (final booking in bookings) {
        final bookingService = ServicesCatalog.getById(booking.serviceId);
        if (bookingService == null) continue;
        
        final bookingStart = booking.appointmentDateTime;
        final bookingEnd = bookingStart.add(Duration(minutes: bookingService.durationMinutes));
        
        // Check for overlap: two time slots overlap if:
        // - The new start is before the existing end AND
        // - The new end is after the existing start
        if (startTime.isBefore(bookingEnd) && endTime.isAfter(bookingStart)) {
          AppLogger.debug('Booking conflict detected: $startTime overlaps with booking ${booking.id}');
          return true;
        }
      }
      
      return false;
    } catch (e, stackTrace) {
      AppLogger.error('Error checking booking conflict', e, stackTrace, 'AppDatabase');
      // On error, assume there's a conflict to be safe
      return true;
    }
  }

  /// Get booking conflicts for a specific date with service durations
  /// Returns a map of time slots and their availability status
  /// Time slots are continuous - next slot starts when previous service ends
  /// The entire duration of each booking is marked as unavailable
  Future<Map<DateTime, bool>> getTimeSlotAvailability(
    DateTime date,
    int durationMinutes,
  ) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day, 7, 0); // 7 AM
      final endOfDay = DateTime(date.year, date.month, date.day, 19, 0); // 7 PM
      
      // Get all active bookings for the day, sorted by start time
      final bookings = await getBookingsForDate(date);
      bookings.sort((a, b) => a.appointmentDateTime.compareTo(b.appointmentDateTime));
      
      // Create a map to track available time slots
      final Map<DateTime, bool> availability = {};
      
      // Create a set of all blocked time periods (entire duration of each booking)
      final List<MapEntry<DateTime, DateTime>> blockedPeriods = [];
      
      for (final booking in bookings) {
        final bookingService = ServicesCatalog.getById(booking.serviceId);
        if (bookingService == null) continue;
        
        final bookingStart = booking.appointmentDateTime;
        final bookingEnd = bookingStart.add(Duration(minutes: bookingService.durationMinutes));
        
        // Store the entire blocked period
        blockedPeriods.add(MapEntry(bookingStart, bookingEnd));
        
        // Mark every 15-minute interval within this booking as unavailable
        DateTime blockTime = bookingStart;
        while (blockTime.isBefore(bookingEnd)) {
          availability[blockTime] = false;
          blockTime = blockTime.add(const Duration(minutes: 15));
        }
      }
      
      // Calculate available slots - only slots that don't overlap with any blocked period
      DateTime currentTime = startOfDay;
      while (currentTime.isBefore(endOfDay)) {
        final slotEnd = currentTime.add(Duration(minutes: durationMinutes));
        
        // Check if this slot would fit before shop closes
        if (slotEnd.isAfter(endOfDay)) {
          currentTime = currentTime.add(const Duration(minutes: 15));
          continue;
        }
        
        // Check if this slot overlaps with any blocked period
        bool isBlocked = false;
        for (final period in blockedPeriods) {
          final periodStart = period.key;
          final periodEnd = period.value;
          
          // Check for overlap: slot overlaps if it starts before period ends AND ends after period starts
          if (currentTime.isBefore(periodEnd) && slotEnd.isAfter(periodStart)) {
            isBlocked = true;
            break;
          }
        }
        
        // Only mark as available if not blocked and not already marked
        if (!isBlocked && !availability.containsKey(currentTime)) {
          availability[currentTime] = true;
        }
        
        // Move to next potential slot (15-minute increments for granularity)
        currentTime = currentTime.add(const Duration(minutes: 15));
      }
      
      return availability;
    } catch (e, stackTrace) {
      AppLogger.error('Error getting time slot availability', e, stackTrace, 'AppDatabase');
      return {};
    }
  }

  /// Get booking details with calculated end time
  /// Returns a map with booking info including start and end times
  Future<Map<String, dynamic>> getBookingWithEndTime(Booking booking) async {
    final service = await getServiceById(booking.serviceId) ?? ServicesCatalog.getById(booking.serviceId);
    if (service == null) {
      return {
        'booking': booking,
        'startTime': booking.appointmentDateTime,
        'endTime': booking.appointmentDateTime,
        'duration': 0,
      };
    }
    
    final startTime = booking.appointmentDateTime;
    final endTime = startTime.add(Duration(minutes: service.durationMinutes));
    
    return {
      'booking': booking,
      'startTime': startTime,
      'endTime': endTime,
      'duration': service.durationMinutes,
    };
  }

  /// Get all bookings for a date with their calculated end times
  Future<List<Map<String, dynamic>>> getBookingsWithEndTimes(DateTime date) async {
    final bookings = await getBookingsForDate(date);
    final List<Map<String, dynamic>> bookingsWithTimes = [];
    
    for (final booking in bookings) {
      final bookingInfo = await getBookingWithEndTime(booking);
      bookingsWithTimes.add(bookingInfo);
    }
    
    return bookingsWithTimes;
  }

  // ---- SERVICE MANAGEMENT ----
  
  /// Get all services from database
  Future<List<Service>> getAllServices() async {
    try {
      final db = await database;
      final rows = await db.query(
        'services',
        where: 'is_active = ?',
        whereArgs: [1],
        orderBy: 'name ASC',
      );
      return rows.map((row) => Service(
        id: row['id'] as String,
        name: row['name'] as String,
        priceKsh: row['price_ksh'] as int,
        durationMinutes: row['duration_minutes'] as int,
      )).toList();
    } catch (e, stackTrace) {
      AppLogger.error('Error getting services', e, stackTrace, 'AppDatabase');
      return [];
    }
  }

  /// Get service by ID
  Future<Service?> getServiceById(String id) async {
    try {
      final db = await database;
      final rows = await db.query(
        'services',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final row = rows.first;
      return Service(
        id: row['id'] as String,
        name: row['name'] as String,
        priceKsh: row['price_ksh'] as int,
        durationMinutes: row['duration_minutes'] as int,
      );
    } catch (e, stackTrace) {
      AppLogger.error('Error getting service by ID', e, stackTrace, 'AppDatabase');
      return null;
    }
  }

  /// Add a new service
  Future<Service> addService(Service service) async {
    try {
      AppLogger.debug('Adding service: ${service.name}');
      final db = await database;
      await db.insert('services', {
        'id': service.id,
        'name': service.name,
        'price_ksh': service.priceKsh,
        'duration_minutes': service.durationMinutes,
        'is_active': 1,
      });
      AppLogger.info('Service added successfully: ${service.id}');
      return service;
    } catch (e, stackTrace) {
      AppLogger.error('Error adding service', e, stackTrace, 'AppDatabase');
      rethrow;
    }
  }

  /// Update an existing service
  Future<void> updateService(Service service) async {
    try {
      AppLogger.debug('Updating service: ${service.id}');
      final db = await database;
      final rowsAffected = await db.update(
        'services',
        {
          'name': service.name,
          'price_ksh': service.priceKsh,
          'duration_minutes': service.durationMinutes,
        },
        where: 'id = ?',
        whereArgs: [service.id],
      );
      if (rowsAffected == 0) {
        throw Exception('Service not found');
      }
      AppLogger.info('Service updated successfully: ${service.id}');
    } catch (e, stackTrace) {
      AppLogger.error('Error updating service', e, stackTrace, 'AppDatabase');
      rethrow;
    }
  }

  /// Delete (deactivate) a service
  Future<void> deleteService(String serviceId) async {
    try {
      AppLogger.debug('Deleting service: $serviceId');
      final db = await database;
      final rowsAffected = await db.update(
        'services',
        {'is_active': 0},
        where: 'id = ?',
        whereArgs: [serviceId],
      );
      if (rowsAffected == 0) {
        throw Exception('Service not found');
      }
      AppLogger.info('Service deleted successfully: $serviceId');
    } catch (e, stackTrace) {
      AppLogger.error('Error deleting service', e, stackTrace, 'AppDatabase');
      rethrow;
    }
  }

  // ---- BOOKING MANAGEMENT ----
  
  /// Update a booking
  Future<void> updateBooking(Booking booking) async {
    try {
      if (booking.id == null) {
        throw Exception('Booking ID is required for update');
      }
      AppLogger.debug('Updating booking: ${booking.id}');
      final db = await database;
      final rowsAffected = await db.update(
        'bookings',
        booking.toMap(),
        where: 'id = ?',
        whereArgs: [booking.id],
      );
      if (rowsAffected == 0) {
        throw Exception('Booking not found');
      }
      AppLogger.info('Booking updated successfully: ${booking.id}');
    } catch (e, stackTrace) {
      AppLogger.error('Error updating booking', e, stackTrace, 'AppDatabase');
      rethrow;
    }
  }

  /// Delete a booking permanently
  Future<void> deleteBooking(int bookingId) async {
    try {
      AppLogger.debug('Deleting booking: $bookingId');
      final db = await database;
      final rowsAffected = await db.delete(
        'bookings',
        where: 'id = ?',
        whereArgs: [bookingId],
      );
      if (rowsAffected == 0) {
        throw Exception('Booking not found');
      }
      AppLogger.info('Booking deleted successfully: $bookingId');
    } catch (e, stackTrace) {
      AppLogger.error('Error deleting booking', e, stackTrace, 'AppDatabase');
      rethrow;
    }
  }

  // ---- ANALYTICS ----
  
  /// Get total number of bookings
  Future<int> getTotalBookings() async {
    try {
      final db = await database;
      final rows = await db.rawQuery(
        "SELECT COUNT(*) as count FROM bookings WHERE status = 'active'",
      );
      return (rows.first['count'] as int?) ?? 0;
    } catch (e, stackTrace) {
      AppLogger.error('Error getting total bookings', e, stackTrace, 'AppDatabase');
      return 0;
    }
  }

  /// Get peak hours (hours with most bookings)
  Future<Map<int, int>> getPeakHours() async {
    try {
      final db = await database;
      final rows = await db.rawQuery('''
        SELECT 
          CAST(strftime('%H', appointment_dt) AS INTEGER) as hour,
          COUNT(*) as count
        FROM bookings
        WHERE status = 'active'
        GROUP BY hour
        ORDER BY count DESC
        LIMIT 5
      ''');
      
      final Map<int, int> peakHours = {};
      for (final row in rows) {
        final hour = row['hour'] as int?;
        final count = row['count'] as int?;
        if (hour != null && count != null) {
          peakHours[hour] = count;
        }
      }
      return peakHours;
    } catch (e, stackTrace) {
      AppLogger.error('Error getting peak hours', e, stackTrace, 'AppDatabase');
      return {};
    }
  }

  /// Get most popular services
  Future<List<Map<String, dynamic>>> getMostPopularServices({int limit = 5}) async {
    try {
      final db = await database;
      final rows = await db.rawQuery('''
        SELECT 
          service_id,
          service_name,
          COUNT(*) as booking_count,
          SUM(price_ksh) as total_revenue
        FROM bookings
        WHERE status = 'active'
        GROUP BY service_id, service_name
        ORDER BY booking_count DESC
        LIMIT ?
      ''', [limit]);
      
      return rows.map((row) => {
        'service_id': row['service_id'] as String,
        'service_name': row['service_name'] as String,
        'booking_count': row['booking_count'] as int,
        'total_revenue': row['total_revenue'] as int,
      }).toList();
    } catch (e, stackTrace) {
      AppLogger.error('Error getting popular services', e, stackTrace, 'AppDatabase');
      return [];
    }
  }

  /// Get total revenue
  Future<int> getTotalRevenue() async {
    try {
      final db = await database;
      final rows = await db.rawQuery(
        "SELECT SUM(price_ksh) as total FROM bookings WHERE status = 'active'",
      );
      return (rows.first['total'] as int?) ?? 0;
    } catch (e, stackTrace) {
      AppLogger.error('Error getting total revenue', e, stackTrace, 'AppDatabase');
      return 0;
    }
  }

  /// Check if a date is fully booked
  Future<bool> isDateFullyBooked(DateTime date) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day, 7, 0); // 7 AM
      final endOfDay = DateTime(date.year, date.month, date.day, 19, 0); // 7 PM
      final totalMinutes = endOfDay.difference(startOfDay).inMinutes;
      
      // Get all active bookings for the day
      final bookings = await getBookingsForDate(date);
      
      // Calculate total booked time
      int totalBookedMinutes = 0;
      for (final booking in bookings) {
        final bookingService = ServicesCatalog.getById(booking.serviceId);
        if (bookingService != null) {
          totalBookedMinutes += bookingService.durationMinutes;
        }
      }
      
      // Consider fully booked if booked time is >= 95% of available time
      // (allowing small gaps for rounding)
      return totalBookedMinutes >= (totalMinutes * 0.95);
    } catch (e, stackTrace) {
      AppLogger.error('Error checking if date is fully booked', e, stackTrace, 'AppDatabase');
      return false;
    }
  }

  /// Get fully booked dates for a month
  Future<Set<DateTime>> getFullyBookedDates(int year, int month) async {
    try {
      final startOfMonth = DateTime(year, month, 1);
      final endOfMonth = DateTime(year, month + 1, 1);
      final Set<DateTime> fullyBookedDates = {};
      
      DateTime currentDate = startOfMonth;
      while (currentDate.isBefore(endOfMonth)) {
        if (await isDateFullyBooked(currentDate)) {
          fullyBookedDates.add(DateTime(currentDate.year, currentDate.month, currentDate.day));
        }
        currentDate = currentDate.add(const Duration(days: 1));
      }
      
      return fullyBookedDates;
    } catch (e, stackTrace) {
      AppLogger.error('Error getting fully booked dates', e, stackTrace, 'AppDatabase');
      return {};
    }
  }
}
