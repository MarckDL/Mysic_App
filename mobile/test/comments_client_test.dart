import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/core/network/authenticated_api_client.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/comments/data/api_comment_repository.dart';
import 'package:mysic/features/comments/domain/comments.dart';

import 'support/fake_auth_repository.dart';

void main() {
  test(
    'envía token y cursor, interpreta 204 y conserva sesión ante 403',
    () async {
      final auth = FakeAuthRepository(user: const AuthUser(uid: 'a'));
      final dio = Dio();
      final requests = <RequestOptions>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            requests.add(request);
            expect(
              request.headers['Authorization'],
              'Bearer firebase-id-token-for-test',
            );
            if (request.path == '/api/v1/moderation/comments') {
              handler.reject(
                DioException(
                  requestOptions: request,
                  type: DioExceptionType.badResponse,
                  response: Response(requestOptions: request, statusCode: 403),
                ),
              );
            } else if (request.method == 'GET') {
              handler.resolve(
                Response(
                  requestOptions: request,
                  statusCode: 200,
                  data: {
                    'items': [
                      {
                        'id': 'comment',
                        'body': 'Texto',
                        'authorName': 'A',
                        'isMine': true,
                      },
                    ],
                    'nextCursor': 'second',
                  },
                ),
              );
            } else {
              handler.resolve(
                Response(requestOptions: request, statusCode: 204),
              );
            }
          },
        ),
      );
      final client = AuthenticatedApiClient(
        auth,
        baseUrl: 'https://mysic.example',
        dio: dio,
        keepSessionOnForbidden: true,
      );
      addTearDown(client.close);
      final repository = ApiCommentRepository(client);

      final page = await repository.list(
        'youtube:abcdefghijk',
        cursor: 'first',
      );
      expect(page.items.single.isMine, isTrue);
      expect(page.nextCursor, 'second');
      await repository.report('comment', ReportReason.spam);
      await repository.remove('comment');
      await repository.resolve('comment', ModerationAction.hide);
      await expectLater(
        repository.queue(),
        throwsA(
          isA<ApiFailure>().having((error) => error.statusCode, 'status', 403),
        ),
      );
      expect(auth.signOutCount, 0);
      expect(requests.first.queryParameters, {'cursor': 'first'});
      expect(requests[1].data, {'reason': 'spam'});
      expect(requests[3].data, {'action': 'hide'});
      expect(requests.map((request) => '${request.method} ${request.path}'), [
        'GET /api/v1/tracks/youtube%3Aabcdefghijk/comments',
        'POST /api/v1/comments/comment/reports',
        'DELETE /api/v1/comments/comment',
        'PATCH /api/v1/moderation/comments/comment',
        'GET /api/v1/moderation/comments',
      ]);
    },
  );
}
