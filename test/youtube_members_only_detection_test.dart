import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/services/youtube_members_only_detection.dart';

void main() {
  test('erkennt den sprachneutralen Members-only-Badge-Stil', () {
    final response = {
      'contents': [
        {
          'videoRenderer': {
            'videoId': 'de-member',
            'title': {
              'runs': [
                {'text': 'Deutscher Titel'},
              ],
            },
            'badges': [
              {
                'metadataBadgeRenderer': {
                  'icon': {'iconType': 'SPONSORSHIP_STAR'},
                  'style': 'BADGE_STYLE_TYPE_MEMBERS_ONLY',
                  'label': 'Nur für Kanalmitglieder',
                },
              },
            ],
          },
        },
      ],
    };

    expect(extractYouTubeMembersOnlyVideoIds(response), {'de-member'});
  });

  test('erkennt englischen Badge-Text als defensiven Fallback', () {
    final response = {
      'videoRenderer': {
        'videoId': 'en-member',
        'badges': [
          {
            'metadataBadgeRenderer': {'label': 'Members only'},
          },
        ],
      },
    };

    expect(extractYouTubeMembersOnlyVideoIds(response), {'en-member'});
  });

  test('erkennt das Sponsorship-Icon ausschließlich im Badge-Kontext', () {
    final memberRenderer = {
      'videoId': 'icon-member',
      'badges': [
        {
          'metadataBadgeRenderer': {
            'icon': {'iconType': 'SPONSORSHIP_STAR'},
          },
        },
      ],
    };
    final publicRenderer = {
      'videoId': 'public-icon',
      'actions': [
        {
          'icon': {'iconType': 'SPONSORSHIP_STAR'},
        },
      ],
    };

    expect(isYouTubeMembersOnlyRenderer(memberRenderer), isTrue);
    expect(isYouTubeMembersOnlyRenderer(publicRenderer), isFalse);
  });

  test('erkennt deutschen Badge-Text als defensiven Fallback', () {
    final response = {
      'playlistVideoRenderer': {
        'videoId': 'de-text-member',
        'badges': [
          {
            'metadataBadgeRenderer': {'label': 'Nur für Kanalmitglieder'},
          },
        ],
      },
    };

    expect(extractYouTubeMembersOnlyVideoIds(response), {'de-text-member'});
  });

  test('erkennt sponsors_only_video in einem Lockup', () {
    final response = {
      'lockupViewModel': {
        'contentId': 'lockup-member',
        'metadata': {
          'offer': {'offerId': 'sponsors_only_video'},
        },
      },
    };

    expect(extractYouTubeMembersOnlyVideoIds(response), {'lockup-member'});
  });

  test('wertet Mitgliedschaftswerbung in Beschreibungen nicht als Sperre', () {
    final publicRenderer = {
      'videoId': 'public-video',
      'title': {
        'runs': [
          {'text': 'Join this channel'},
        ],
      },
      'descriptionSnippet': {
        'runs': [
          {'text': 'Join this channel to support us. Members only extras.'},
          {
            'text':
                'BADGE_STYLE_TYPE_MEMBERS_ONLY and sponsors_only_video docs.',
          },
        ],
      },
    };

    expect(isYouTubeMembersOnlyRenderer(publicRenderer), isFalse);
  });

  test('extrahiert deutsche und englische Raw-Renderer', () {
    const raw = r'''
      <script>var ytInitialData = {"contents":[
        {"videoRenderer":{"videoId":"de-raw","badges":[
          {"metadataBadgeRenderer":{"style":"BADGE_STYLE_TYPE_MEMBERS_ONLY",
          "label":"Nur f\u00fcr Kanalmitglieder"}}]}},
        {"lockupViewModel":{"contentId":"en-raw","metadata":{
          "badge":{"label":"Members only"}}}},
        {"videoRenderer":{"videoId":"public-raw","title":{"simpleText":
          "Members only is discussed here"}}}
      ]};</script>
    ''';

    expect(extractYouTubeMembersOnlyVideoIds(raw), {'de-raw', 'en-raw'});
  });

  test('erkennt deutsche und englische Playability-Antworten', () {
    expect(
      isYouTubeMembersOnlyPlaybackFailure(
        'Join this channel to get access to members-only content like this video.',
      ),
      isTrue,
    );
    expect(
      isYouTubeMembersOnlyPlaybackFailure(
        'Werde Kanalmitglied, um Zugriff auf dieses Video zu erhalten.',
      ),
      isTrue,
    );
    expect(isYouTubeMembersOnlyPlaybackFailure('Video unavailable'), isFalse);
  });
}
