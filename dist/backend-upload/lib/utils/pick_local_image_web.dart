import 'dart:async';
import 'dart:html' as html;
import 'dart:math' as math;

class PickedStoreImage {
  const PickedStoreImage({
    required this.base64,
    required this.contentType,
  });

  final String base64;
  final String contentType;
}

Future<PickedStoreImage?> pickLocalStoreImage() async {
  final input = html.FileUploadInputElement()
    ..accept = 'image/*'
    ..style.display = 'none';
  html.document.body?.append(input);
  input.click();
  await input.onChange.first;
  final file = input.files?.first;
  input.remove();
  if (file == null) return null;

  final reader = html.FileReader();
  final loaded = Completer<String>();
  reader.onError.listen((_) {
    if (!loaded.isCompleted) {
      loaded.completeError(Exception('تعذر قراءة الصورة'));
    }
  });
  reader.onLoad.listen((_) {
    loaded.complete(reader.result as String);
  });
  reader.readAsDataUrl(file);
  final dataUrl = await loaded.future;
  return _compressToJpeg(dataUrl);
}

Future<PickedStoreImage> _compressToJpeg(String dataUrl) async {
  final image = html.ImageElement();
  final ready = Completer<void>();
  image.onError.listen((_) {
    if (!ready.isCompleted) ready.completeError(Exception('صورة غير صالحة'));
  });
  image.onLoad.listen((_) {
    if (!ready.isCompleted) ready.complete();
  });
  image.src = dataUrl;
  await ready.future;

  const maxWidth = 1600.0;
  final srcW = image.naturalWidth.toDouble();
  final srcH = image.naturalHeight.toDouble();
  final scale = srcW > maxWidth ? maxWidth / srcW : 1.0;
  final width = math.max(1, (srcW * scale).round());
  final height = math.max(1, (srcH * scale).round());

  final canvas = html.CanvasElement(width: width, height: height);
  final ctx = canvas.context2D;
  ctx.drawImageScaled(image, 0, 0, width, height);
  final jpeg = canvas.toDataUrl('image/jpeg', 0.82);
  final comma = jpeg.indexOf(',');
  final base64 = comma >= 0 ? jpeg.substring(comma + 1) : jpeg;
  return PickedStoreImage(base64: base64, contentType: 'image/jpeg');
}
