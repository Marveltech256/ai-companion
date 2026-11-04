import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../billing/billing_controller.dart';
import 'actions.dart';

Future<void> membershipDialog(
  BuildContext context,
  BillingController billing,
) async {
  billing.load();
  await showMorrowDialog<void>(
    context: context,
    builder: (context) => AnimatedBuilder(
      animation: billing,
      builder: (context, _) {
        final s = billing.status, premium = s?['premium'] == true;
        return AlertDialog(
          title: const Text('Your membership'),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (billing.busy) const LinearProgressIndicator(),
                  if (s != null)
                    Text(
                      premium
                          ? 'Premium is active.'
                          : s['mode'] == 'introductory'
                          ? 'Your introductory access is active.'
                          : s['mode'] == 'expired'
                          ? 'Your introductory access has ended.'
                          : 'Your current access is free during testing.',
                    ),
                  if (s?['trial_ends_at'] != null &&
                      s?['mode'] == 'introductory')
                    Text(
                      'Introductory access ends ${DateTime.parse(s!['trial_ends_at'] as String).toLocal()}.',
                    ),
                  if (s?['messages_limit'] != null)
                    Text(
                      '${s!['messages_used_today']} of ${s['messages_limit']} messages used today. Daily allowances reset at 00:00 UTC.',
                    ),
                  if (billing.plan != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      billing.plan!.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text('${billing.plan!.price} / month'),
                    const Text(
                      'Renews monthly through Google Play unless you cancel. Review the final price and terms in Google Play before confirming.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: billing.busy || billing.pending || premium
                          ? null
                          : billing.buy,
                      child: Text(
                        billing.pending
                            ? 'Waiting for Google Play…'
                            : 'Continue with monthly plan',
                      ),
                    ),
                  ],
                  if (s?['available'] == true && !billing.store.supported)
                    const Text(
                      'Purchases are available in the Android app through Google Play.',
                    ),
                  if (billing.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(billing.error!.message),
                    ),
                  if (billing.store.supported && s?['available'] == true)
                    TextButton(
                      onPressed: billing.busy || billing.pending
                          ? null
                          : billing.restore,
                      child: const Text('Restore purchases'),
                    ),
                  TextButton(
                    onPressed: () async {
                      final opened = await launchUrl(
                        Uri.https(
                          'play.google.com',
                          '/store/account/subscriptions',
                          {'package': 'com.aipersonalcompanion'},
                        ),
                        mode: LaunchMode.externalApplication,
                      );
                      if (!opened && context.mounted) {
                        showMessage(
                          context,
                          'Google Play could not be opened.',
                        );
                      }
                    },
                    child: const Text('Manage or cancel in Google Play'),
                  ),
                  TextButton(
                    onPressed: billing.busy || billing.pending
                        ? null
                        : () => billing.load(refresh: true),
                    child: const Text('Refresh membership'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    ),
  );
}
