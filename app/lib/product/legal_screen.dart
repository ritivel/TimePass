import 'package:flutter/material.dart';

enum LegalDocument { privacy, terms }

class LegalScreen extends StatelessWidget {
  const LegalScreen({required this.document, super.key});

  final LegalDocument document;

  static const supportEmail = String.fromEnvironment(
    'NAKUL_SUPPORT_EMAIL',
    defaultValue: 'support@nakul.app',
  );

  @override
  Widget build(BuildContext context) {
    final privacy = document == LegalDocument.privacy;
    return Scaffold(
      appBar: AppBar(title: Text(privacy ? 'Privacy Policy' : 'Terms of Use')),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
          children: [
            Text(
              'Effective 12 July 2026',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 20),
            if (privacy) ..._privacy(context) else ..._terms(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _privacy(BuildContext context) => [
    _section(
      context,
      'What we collect',
      'We store your account email, chat questions, generated answer data, bookmarks, language preference, and basic product events. Voice recordings are sent for transcription and are not intentionally retained by Nakul after the request completes.',
    ),
    _section(
      context,
      'Why we use it',
      'We use this data to provide answers, sync your history, operate voice features, prevent abuse, diagnose failures, and improve the product. We do not sell personal information.',
    ),
    _section(
      context,
      'Processors and international transfer',
      'Nakul uses Supabase for authentication and storage, Render for the API, Cloudflare for delivery and security, Google Gemini for answer generation, and Sarvam for speech services. Requests may be processed outside India under the safeguards offered by those providers.',
    ),
    _section(
      context,
      'Retention and control',
      'Chats remain until you delete them or your account. Anonymous accounts that are not converted are deleted after 30 days, and basic product events are deleted after 90 days. Infrastructure providers may keep operational logs under their own retention policies. You can copy your data, delete individual chats, and permanently delete your account from Account settings.',
    ),
    _section(
      context,
      'Your choices',
      'You may access, correct, export, or erase your data and withdraw consent by deleting your account. For privacy or grievance requests, contact $supportEmail.',
    ),
    _section(
      context,
      'Children',
      'Nakul is not directed to children under 13. If you believe a child has provided personal data, contact us so it can be removed.',
    ),
  ];

  List<Widget> _terms(BuildContext context) => [
    _section(
      context,
      'The service',
      'Nakul provides AI-generated informational answers and interactive utilities. Outputs can be incomplete or wrong and may change as underlying information changes.',
    ),
    _section(
      context,
      'Important decisions',
      'Do not treat Nakul as professional medical, legal, financial, emergency, or safety advice. Verify important information with a qualified professional or an authoritative source.',
    ),
    _section(
      context,
      'Acceptable use',
      'Do not use the service to break the law, harm others, probe or bypass security, automate abusive traffic, upload content you lack rights to use, or interfere with the service.',
    ),
    _section(
      context,
      'Your content',
      'You retain rights in your questions. You give Nakul the limited permission needed to process them and return an answer. You are responsible for content you submit.',
    ),
    _section(
      context,
      'Availability and accounts',
      'The service may change or be interrupted. Keep your account credentials secure. We may restrict abusive accounts, and you may delete your account at any time.',
    ),
    _section(
      context,
      'Contact',
      'Questions about these terms can be sent to $supportEmail.',
    ),
  ];

  Widget _section(BuildContext context, String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(body, style: const TextStyle(height: 1.55)),
      ],
    ),
  );
}
