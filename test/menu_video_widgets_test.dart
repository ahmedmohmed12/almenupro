import 'package:almenupro/models/menu_item.dart';
import 'package:almenupro/widgets/menu/video/menu_video_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MenuItem _item({
  String webm = '',
  String mp4 = '',
  bool story = false,
}) {
  return MenuItem(
    id: 1,
    categoryId: 1,
    categoryName: 'Signature',
    name: 'Signature dish',
    description: '',
    price: 3.5,
    imageUrl: '',
    videoUrlWebm: webm,
    videoUrlMp4: mp4,
    isStory: story,
    isAvailable: true,
  );
}

void main() {
  test('MenuItem round-trips video and story fields', () {
    final source = _item(
      webm: 'https://cdn.example.com/dish.webm',
      mp4: 'https://cdn.example.com/dish.mp4',
      story: true,
    );
    final restored = MenuItem.fromJson(source.toJson());

    expect(restored.videoUrlWebm, source.videoUrlWebm);
    expect(restored.videoUrlMp4, source.videoUrlMp4);
    expect(restored.isStory, isTrue);
    expect(restored.hasVideo, isTrue);
  });

  testWidgets('video controller is absent before explicit badge tap', (
    tester,
  ) async {
    final source = _item(webm: 'https://cdn.example.com/dish.webm');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ItemVideoBadge(item: source)),
      ),
    );

    expect(find.byType(ItemVideoBadge), findsOneWidget);
    expect(find.byType(LazyVideoPlayer), findsNothing);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('stories bar only shows opted-in video items', (tester) async {
    final story = _item(
      webm: 'https://cdn.example.com/story.webm',
      story: true,
    );
    final regular = MenuItem(
      id: 2,
      categoryId: 1,
      categoryName: 'Other',
      name: 'Regular dish',
      description: '',
      price: 2,
      imageUrl: '',
      isAvailable: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeaturedStoriesBar(
            items: [story, regular],
            onAdd: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Signature dish'), findsOneWidget);
    expect(find.text('Regular dish'), findsNothing);
    expect(find.byType(LazyVideoPlayer), findsNothing);
  });
}
