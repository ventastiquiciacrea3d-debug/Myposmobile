// Script de prueba para verificar si el endpoint /batch/stock existe
import 'dart:io';
import 'dart:convert';

void main() async {
  final url = 'https://tcrea3d.com/wp-json/mypos/v1/batch/stock';
  final token = 'Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJodHRwczovL3RjcmVhM2QuY29tIiwiYXVkIjoibXktcG9zLW1vYmlsZS1hcHAiLCJpYXQiOjE3NjQzOTUwNzUsIm5iZiI6MTc2NDM5NTA3NSwiZXhwIjoxNzY1NjA0Njc1LCJkYXRhIjp7ImRldmljZV91dWlkIjoiYjhkZDBkMTctZGUzYy00YTc4LWEyODAtNmU3YTc3NTIwM2ZkIn19.kNCLHRLARwK4tkzYjCdmw1uFXbSueaJxlEpkywjMpfg';

  try {
    final client = HttpClient();
    final request = await client.postUrl(Uri.parse(url));

    request.headers.set('Content-Type', 'application/json');
    request.headers.set('Authorization', token);

    // Enviar un payload de prueba
    final payload = jsonEncode({
      'items': [
        {'id': 1, 'stock': 10, 'operation': 'set'}
      ]
    });

    request.write(payload);

    print('🔍 Probando endpoint: $url');
    print('📦 Payload: $payload');
    print('');

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();

    print('📊 STATUS CODE: ${response.statusCode}');
    print('📄 RESPONSE:');
    print(responseBody);
    print('');

    if (response.statusCode == 404) {
      print('❌ ERROR: El endpoint NO existe en el servidor');
      print('💡 Asegúrate de haber actualizado el plugin WordPress');
    } else if (response.statusCode == 200) {
      print('✅ SUCCESS: El endpoint existe y responde correctamente');
    } else {
      print('⚠️  RESPONSE: ${response.statusCode} - Verifica los logs');
    }

    client.close();
  } catch (e) {
    print('❌ ERROR: $e');
  }
}
