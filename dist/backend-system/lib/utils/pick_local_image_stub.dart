class PickedStoreImage {
  const PickedStoreImage({
    required this.base64,
    required this.contentType,
  });

  final String base64;
  final String contentType;
}

Future<PickedStoreImage?> pickLocalStoreImage() async => null;
