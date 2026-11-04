import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_companion/auth/review_guest.dart';
import 'package:ai_companion/app/companion_controller.dart';
import 'package:ai_companion/application/application.dart';
import 'package:ai_companion/application/connection.dart';
import 'package:ai_companion/application/sign_in_page.dart';
import 'package:ai_companion/core/app_failure.dart';

import 'support/account_services.dart';
import 'application_test.dart' as review show loadFonts, viewport, capture;

class ReviewSession extends AccountTestSession implements ReviewGuestGateway {
  bool enabled = true;
  @override
  bool isReviewGuest = false;
  int entries = 0;
  @override
  Future<bool> reviewGuestAvailable() async => enabled;
  @override
  Future<void> signInReviewGuest(String code, {bool renew = false}) async {
    if (!enabled) {
      throw const AppFailure(
        'review_unavailable',
        'Guest review access is not available.',
      );
    }
    if (code != 'synthetic-private-code') {
      throw const AppFailure(
        'invalid_review_code',
        'The review access code was not accepted.',
      );
    }
    entries++;
    if (!renew) {
      isAnonymous = false;
      isReviewGuest = true;
      switchUser('review_synthetic_owner');
    }
  }

  @override
  Future<void> signOut() async {
    isReviewGuest = false;
    await super.signOut();
  }
}

void main() {
  setUpAll(review.loadFonts);
  testWidgets(
    'review guest entry is hidden when disabled and a wrong code cannot pass sign-in',
    (tester) async {
      final session = ReviewSession()..switchUser(null);
      final api = AccountTestApi(session)..companion = null;
      final controller = CompanionController(session: session, api: api);
      await tester.pumpWidget(
        MorrowApplication(
          connection: AppConnection(
            controller: controller,
            deviceOnly: false,
            closeSession: session.events.close,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Guest for app review'), findsNothing);
      await controller.refreshReviewGuestAvailability();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guest for app review'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.tap(find.text('Continue as guest'));
      await tester.pumpAndSettle();
      expect(
        find.text('The review access code was not accepted.'),
        findsOneWidget,
      );
      expect(controller.userId, isNull);
      expect(find.byType(SignInPage), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      session.enabled = false;
      await controller.refreshReviewGuestAvailability();
      await tester.pumpAndSettle();
      expect(find.text('Guest for app review'), findsNothing);
      expect(session.entries, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'valid review entry keeps adult onboarding and sign-out locks the app again',
    (tester) async {
      review.viewport(tester, const Size(390, 844));
      final session = ReviewSession()..switchUser(null);
      final api = AccountTestApi(session)..companion = null;
      final controller = CompanionController(session: session, api: api);
      await controller.refreshReviewGuestAvailability();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('application-capture'),
          child: MorrowApplication(
            connection: AppConnection(
              controller: controller,
              deviceOnly: false,
              closeSession: session.events.close,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await review.capture(tester, 'review-guest-welcome');
      await tester.tap(find.text('Guest for app review'));
      await tester.pumpAndSettle();
      await review.capture(tester, 'review-guest-code');
      await tester.enterText(find.byType(TextField), 'synthetic-private-code');
      await tester.tap(find.text('Continue as guest'));
      await tester.pumpAndSettle();
      expect(controller.reviewGuestAccount, true);
      expect(controller.registeredAccount, true);
      expect(controller.personalProfile.preferredName, 'Reviewer');
      expect(controller.needsIntroduction, true);
      expect(find.byType(SignInPage), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      await controller.signOut();
      await tester.pumpAndSettle();
      expect(find.byType(SignInPage), findsOneWidget);
      expect(controller.reviewGuestAccount, false);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
