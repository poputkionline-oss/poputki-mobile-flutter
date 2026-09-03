import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  static const String baseUrl = 'https://poputki-backend.onrender.com/api';

  late Dio _dio;

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      headers: {
        'Content-Type': 'application/json',
      },
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        
        final adminToken = prefs.getString('adminToken');
        if (adminToken != null) {
          options.headers['X-Admin-Token'] = adminToken;
        }
        return handler.next(options);
      },
      onError: (DioException e, handler) {
        // Handle global errors here if needed (e.g. 401 logout)
        return handler.next(e);
      },
    ));
  }

  Dio get dio => _dio;

  // Simple GET wrapper
  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) async {
    return await _dio.get(path, queryParameters: queryParameters);
  }

  // Simple POST wrapper
  Future<Response> post(String path, {dynamic data}) async {
    return await _dio.post(path, data: data);
  }

  // Simple DELETE wrapper
  Future<Response> delete(String path, {dynamic data}) async {
    return await _dio.delete(path, data: data);
  }
}
