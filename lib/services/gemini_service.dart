import 'dart:developer';
import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  GeminiService({required String apiKey})
    : _model = GenerativeModel(model: 'gemini-2.5-flash-lite', apiKey: apiKey);

  final GenerativeModel _model;

  Future<String> analyzeHotel({
    required Uint8List imageBytes,
    String? hotelName,
  }) async {
    final prompt = StringBuffer(
      'Analiza la imagen del hotel y proporciona un resumen honesto. '
      'Incluye una valoracion general (Excelente, Bueno, Regular o Malo), '
      'describe los servicios visibles y menciona posibles inconvenientes. ',
    );

    if (hotelName != null && hotelName.trim().isNotEmpty) {
      prompt.write(
        'El hotel se llama "$hotelName". Incluye recomendaciones breves '
        'para un viajero que quiera hospedarse alli.',
      );
    }

    try {
      final response = await _model.generateContent([
        Content.multi([
          TextPart(prompt.toString()),
          DataPart('image/jpeg', imageBytes),
        ]),
      ]);

      final text = response.text?.trim();
      if (text == null || text.isEmpty) {
        return 'No se pudo generar una descripcion del hotel.';
      }

      return text;
    } catch (error, stackTrace) {
      log('Gemini analysis error: $error', stackTrace: stackTrace);
      rethrow;
    }
  }
}
