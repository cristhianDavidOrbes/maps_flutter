import 'dart:developer';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/active_route.dart';

class RouteService {
  RouteService({SupabaseClient? client, this.table = 'user_routes'})
    : _client = client;

  final SupabaseClient? _client;
  final String table;

  Future<String?> ensureUser() async {
    final client = _client;
    if (client == null) {
      log('Supabase client not available, skipping user creation');
      return null;
    }

    try {
      final currentUser = client.auth.currentUser;
      if (currentUser != null) {
        return currentUser.id;
      }

      final response = await client.auth.signInAnonymously();
      return response.user?.id;
    } catch (error, stackTrace) {
      log('Error ensuring Supabase user: $error', stackTrace: stackTrace);
      return null;
    }
  }

  Future<ActiveRoute?> fetchActiveRoute(String userId) async {
    final client = _client;
    if (client == null) {
      return null;
    }

    try {
      final response = await client
          .from(table)
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return ActiveRoute.fromJson(response as Map<String, dynamic>);
    } on PostgrestException catch (error, stackTrace) {
      log(
        'Supabase error fetching route: ${error.message}',
        stackTrace: stackTrace,
      );
      return null;
    } catch (error, stackTrace) {
      log('Unexpected error fetching route: $error', stackTrace: stackTrace);
      return null;
    }
  }

  Future<void> saveRoute(String userId, ActiveRoute route) async {
    final client = _client;
    if (client == null) {
      return;
    }

    try {
      await client.from(table).upsert(<String, dynamic>{
        'user_id': userId,
        ...route.toJson(),
      });
    } on PostgrestException catch (error, stackTrace) {
      log(
        'Supabase error saving route: ${error.message}',
        stackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      log('Unexpected error saving route: $error', stackTrace: stackTrace);
    }
  }

  Future<void> clearRoute(String userId) async {
    final client = _client;
    if (client == null) {
      return;
    }

    try {
      await client.from(table).delete().eq('user_id', userId);
    } on PostgrestException catch (error, stackTrace) {
      log(
        'Supabase error clearing route: ${error.message}',
        stackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      log('Unexpected error clearing route: $error', stackTrace: stackTrace);
    }
  }
}
