import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

/// Local cache for fuel prices to reduce API calls.
/// Prices are cached for 24 hours.
class FuelPriceCache {
  static const _storage = FlutterSecureStorage();
  static const _pricesCacheKey = 'fuel_prices_cache';
  static const _pricesCacheTimeKey = 'fuel_prices_cache_time';
  static const _cacheDurationHours = 24;

  /// Get cached fuel prices if they exist and are fresh (< 24 hours old)
  static Future<Map<String, double>?> getCachedPrices() async {
    try {
      final cached = await _storage.read(key: _pricesCacheKey);
      final cacheTime = await _storage.read(key: _pricesCacheTimeKey);

      if (cached == null || cacheTime == null) {
        return null;
      }

      final cachedAt = DateTime.parse(cacheTime);
      final now = DateTime.now();
      final hoursDiff = now.difference(cachedAt).inHours;

      // Cache expired
      if (hoursDiff >= _cacheDurationHours) {
        await clearCache();
        return null;
      }

      // Cache is still valid
      final data = jsonDecode(cached) as Map<String, dynamic>;
      return Map<String, double>.from(
        data.map((k, v) => MapEntry(k, (v as num).toDouble())),
      );
    } catch (e) {
      return null;
    }
  }

  /// Save fuel prices to cache
  static Future<void> cachePrices(Map<String, double> prices) async {
    try {
      await _storage.write(
        key: _pricesCacheKey,
        value: jsonEncode(prices),
      );
      await _storage.write(
        key: _pricesCacheTimeKey,
        value: DateTime.now().toIso8601String(),
      );
    } catch (e) {
      // Silently fail if cache write fails
    }
  }

  /// Clear the cache
  static Future<void> clearCache() async {
    try {
      await _storage.delete(key: _pricesCacheKey);
      await _storage.delete(key: _pricesCacheTimeKey);
    } catch (e) {
      // Silently fail
    }
  }

  /// Get prices with fallback to cache if API fails
  static Future<Map<String, double>> getPricesWithFallback() async {
    try {
      // Try to get fresh prices from API
      final freshPrices = await _getFreshPrices();
      if (freshPrices.isNotEmpty) {
        await cachePrices(freshPrices);
        return freshPrices;
      }
    } catch (e) {
      // API failed, try cache
    }

    // Fallback to cached prices
    final cachedPrices = await getCachedPrices();
    if (cachedPrices != null) {
      return cachedPrices;
    }

    // No cache available, return empty (caller should handle)
    return {};
  }

  /// Fetch fresh prices from API (internal)
  static Future<Map<String, double>> _getFreshPrices() async {
    // This is a placeholder - actual implementation in ApiService
    return {};
  }
}