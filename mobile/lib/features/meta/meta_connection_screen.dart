import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shreeram_crm/core/network/api_client.dart';
import 'package:shreeram_crm/core/theme/app_theme.dart';
import 'package:shreeram_crm/shared/widgets/ui_kit.dart';

final metaConnectionProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final res = await ref.watch(dioProvider).get('/meta/connection');
  return Map<String, dynamic>.from(res.data['data'] as Map);
});

class MetaConnectionScreen extends ConsumerStatefulWidget {
  const MetaConnectionScreen({super.key});

  @override
  ConsumerState<MetaConnectionScreen> createState() => _MetaConnectionScreenState();
}

class _MetaConnectionScreenState extends ConsumerState<MetaConnectionScreen> {
  final _appId = TextEditingController();
  final _appSecret = TextEditingController();
  final _pageId = TextEditingController();
  final _pageName = TextEditingController();
  final _pageToken = TextEditingController();
  final _verifyToken = TextEditingController();
  final _formId = TextEditingController();
  final _formName = TextEditingController();
  bool _saving = false;
  bool _hydrated = false;
  String? _message;

  @override
  void dispose() {
    _appId.dispose();
    _appSecret.dispose();
    _pageId.dispose();
    _pageName.dispose();
    _pageToken.dispose();
    _verifyToken.dispose();
    _formId.dispose();
    _formName.dispose();
    super.dispose();
  }

  void _hydrate(Map<String, dynamic> data) {
    if (_hydrated) return;
    _hydrated = true;
    _appId.text = '${data['app_id'] ?? ''}';
    _pageId.text = '${data['page_id'] ?? ''}';
    _pageName.text = '${data['page_name'] ?? ''}';
  }

  Future<void> _generateToken() async {
    final res = await ref.read(dioProvider).post('/meta/webhook-token');
    setState(() {
      _verifyToken.text = '${res.data['webhook_verify_token']}';
      _message = 'Verify token generated. Save connection so Meta can verify the webhook.';
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await ref.read(dioProvider).post('/meta/connection', data: {
        'app_id': _appId.text.trim(),
        if (_appSecret.text.trim().isNotEmpty) 'app_secret': _appSecret.text.trim(),
        'page_id': _pageId.text.trim(),
        'page_name': _pageName.text.trim(),
        if (_pageToken.text.trim().isNotEmpty) 'page_access_token': _pageToken.text.trim(),
        if (_verifyToken.text.trim().isNotEmpty) 'webhook_verify_token': _verifyToken.text.trim(),
        'status': 'connected',
      });

      if (_formId.text.trim().isNotEmpty) {
        await ref.read(dioProvider).post('/meta/forms/sync', data: {
          'forms': [
            {
              'form_id': _formId.text.trim(),
              'form_name': _formName.text.trim().isEmpty ? null : _formName.text.trim(),
              'is_active': true,
            }
          ],
        });
      }

      _hydrated = false;
      ref.invalidate(metaConnectionProvider);
      setState(() => _message = 'Meta connection saved. Complete webhook subscription in Meta Developer Console.');
    } catch (e) {
      setState(() => _message = 'Could not save connection. Check fields and try again.');
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(metaConnectionProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Unable to load Meta settings: $e')),
      data: (data) {
        _hydrate(data);
        final connected = data['status'] == 'connected';
        final webhookUrl = '${data['webhook_callback_url'] ?? ''}';
        final steps = (data['setup_steps'] as List<dynamic>? ?? []).map((e) => '$e').toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
          children: [
            FadeSlideIn(
              child: SectionHeader(
                title: 'Meta Lead Ads',
                subtitle: 'Connect once. New form submissions flow into ShreeRam automatically.',
                action: StatusPill(
                  label: connected ? 'Connected' : 'Not connected',
                  positive: connected,
                ),
              ),
            ),
            const SizedBox(height: 20),
            FadeSlideIn(
              delay: const Duration(milliseconds: 60),
              child: SoftPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Webhook callback URL', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    SelectableText(
                      webhookUrl,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppTheme.forest),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: webhookUrl));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Webhook URL copied')),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copy URL'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Paste this URL in Meta → Webhooks → Callback URL. Use the verify token generated below.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FadeSlideIn(
              delay: const Duration(milliseconds: 100),
              child: SoftPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Setup checklist', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    for (var i = 0; i < steps.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: AppTheme.forest.withValues(alpha: 0.1),
                              child: Text('${i + 1}', style: const TextStyle(fontSize: 12, color: AppTheme.forest)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(steps[i], style: Theme.of(context).textTheme.bodyMedium)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Connection details', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            SoftPanel(
              child: Column(
                children: [
                  TextField(controller: _appId, decoration: const InputDecoration(labelText: 'Meta App ID')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _appSecret,
                    decoration: InputDecoration(
                      labelText: data['has_app_secret'] == true
                          ? 'App Secret (leave blank to keep existing)'
                          : 'App Secret',
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: _pageId, decoration: const InputDecoration(labelText: 'Facebook Page ID')),
                  const SizedBox(height: 12),
                  TextField(controller: _pageName, decoration: const InputDecoration(labelText: 'Page Name')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pageToken,
                    decoration: InputDecoration(
                      labelText: data['has_page_token'] == true
                          ? 'Page Access Token (leave blank to keep existing)'
                          : 'Page Access Token',
                    ),
                    obscureText: true,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _verifyToken,
                          decoration: InputDecoration(
                            labelText: data['has_verify_token'] == true
                                ? 'Webhook Verify Token (new value replaces old)'
                                : 'Webhook Verify Token',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: _generateToken,
                        child: const Text('Generate'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Lead form', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Only register forms you want this CRM to accept. Campaign/Ad IDs arrive automatically with each lead.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            SoftPanel(
              child: Column(
                children: [
                  TextField(controller: _formId, decoration: const InputDecoration(labelText: 'Lead Form ID')),
                  const SizedBox(height: 12),
                  TextField(controller: _formName, decoration: const InputDecoration(labelText: 'Form Name (optional)')),
                ],
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 14),
              Text(_message!, style: TextStyle(color: AppTheme.forestMid, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.link_rounded),
                label: Text(_saving ? 'Saving…' : 'Save Meta connection'),
              ),
            ),
          ],
        );
      },
    );
  }
}
