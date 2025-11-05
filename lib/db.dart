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
      } else {
        // Try to get databases path - this will fail on desktop if factory isn't set
        try {
          await getDatabasesPath();
        } catch (_) {
          // On desktop platforms, we need to initialize FFI
          try {
            sqfliteFfiInit();
            databaseFactory = databaseFactoryFfi;
          } catch (_) {
            // FFI init failed, will use default sqflite
          }
        }
      }
    } catch (e) {
      // If all else fails, try to initialize FFI for desktop
      if (!kIsWeb) {
        try {
          sqfliteFfiInit();
          databaseFactory = databaseFactoryFfi;
        } catch (_) {
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
            version: 3,
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
      version: 3,
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
    await _ensureSchema(db);
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
        appointment_dt TEXT NOT NULL
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
    await _ensureOwnerExists(db);
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
    final db = await database;
    final newId = await db.insert('bookings', booking.toMap());
    return booking.copyWith(id: newId);
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

  Future<void> createUser(String username, String password) async {
    final db = await database;
    final exists = await usernameExists(username);
    if (exists) {
      throw Exception('Username already exists');
    }
    // First user becomes 'owner', others 'viewer'
    final ownersRows = await db.rawQuery(
      "SELECT COUNT(*) as c FROM users WHERE role = 'owner'",
    );
    final ownersCount = (ownersRows.first['c'] as int?) ?? 0;
    final role = ownersCount == 0 ? 'owner' : 'viewer';
    final salt = _generateSalt();
    final hash = _hashPassword(password, salt);
    await db.insert('users', {
      'username': username,
      'password_hash': hash,
      'salt': salt,
      'created_at': DateTime.now().toIso8601String(),
      'role': role,
    });
  }

  Future<bool> validateLogin(String username, String password) async {
    final db = await database;
    final rows = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final salt = rows.first['salt'] as String;
    final expected = rows.first['password_hash'] as String;
    final provided = _hashPassword(password, salt);
    return provided == expected;
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
    final db = await database;
    await db.update(
      'bookings',
      {'status': 'cancelled'},
      where: 'id = ?',
      whereArgs: [id],
    );
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
}
