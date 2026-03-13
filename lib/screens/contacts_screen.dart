import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/api_service.dart';
import '../widgets/glass_card.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Map<String, dynamic>> _contacts = [];
  bool _loading = true;

  // Twilio WhatsApp expects E.164 format, e.g. +919771305405.
  String _normalizePhone(String input) {
    final cleaned = input.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) return cleaned;

    if (cleaned.startsWith('+')) return cleaned;
    if (cleaned.startsWith('00')) return '+${cleaned.substring(2)}';
    if (cleaned.length == 10) return '+91$cleaned';
    return '+$cleaned';
  }

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() => _loading = true);
    final result = await ApiService.getContacts();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.success && result.data != null) {
        _contacts = List<Map<String, dynamic>>.from(
          result.data!['contacts'] ?? [],
        );
      }
    });
  }

  Future<void> _deleteContact(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Contact'),
        content: const Text('Remove this emergency contact?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final result = await ApiService.deleteContact(id);
    if (!mounted) return;

    if (result.success) {
      _loadContacts();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Failed to delete'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _editContact(Map<String, dynamic> contact) async {
    final id = contact['id'];
    if (id is! int) return;

    final nameCtrl = TextEditingController(
      text: contact['name'] as String? ?? '',
    );
    final phoneCtrl = TextEditingController(
      text: contact['phone'] as String? ?? '',
    );
    final telegramCtrl = TextEditingController(
      text: contact['telegram_id'] as String? ?? '',
    );
    final relationCtrl = TextEditingController(
      text: contact['relationship'] as String? ?? '',
    );
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Emergency Contact'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number *',
                    prefixIcon: Icon(Icons.phone),
                    hintText: '+91XXXXXXXXXX',
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    final normalized = _normalizePhone(v.trim());
                    final digits = normalized.replaceAll(RegExp(r'[^0-9]'), '');
                    if (digits.length < 10) return 'Enter a valid phone';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: telegramCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Telegram Chat ID',
                    prefixIcon: Icon(Icons.telegram),
                    hintText: 'Optional',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: relationCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Relationship',
                    prefixIcon: Icon(Icons.group),
                    hintText: 'e.g. Father, Mother, Friend',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              final result = await ApiService.updateContact(
                id: id,
                name: nameCtrl.text.trim(),
                phone: _normalizePhone(phoneCtrl.text.trim()),
                telegramId: telegramCtrl.text.trim().isNotEmpty
                    ? telegramCtrl.text.trim()
                    : null,
                relationship: relationCtrl.text.trim().isNotEmpty
                    ? relationCtrl.text.trim()
                    : null,
              );

              if (!mounted) return;
              if (result.success) {
                Navigator.pop(ctx);
                _loadContacts();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Contact updated'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result.error ?? 'Failed to update contact'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Add Manually'),
              subtitle: const Text('Type in contact details'),
              onTap: () {
                Navigator.pop(ctx);
                _showAddContactForm();
              },
            ),
            ListTile(
              leading: const Icon(Icons.contacts),
              title: const Text('Import from Phone'),
              subtitle: const Text('Pick from your phone contacts'),
              onTap: () {
                Navigator.pop(ctx);
                _importFromPhone();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importFromPhone() async {
    // Request permission via permission_handler
    var status = await Permission.contacts.status;
    if (!status.isGranted) {
      status = await Permission.contacts.request();
    }

    if (!status.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status.isPermanentlyDenied
                ? 'Contacts permission permanently denied. Enable in Settings.'
                : 'Contacts permission denied',
          ),
          backgroundColor: Colors.red,
          action: status.isPermanentlyDenied
              ? SnackBarAction(
                  label: 'Settings',
                  textColor: Colors.white,
                  onPressed: openAppSettings,
                )
              : null,
        ),
      );
      return;
    }

    final contacts = await FlutterContacts.getContacts(
      withProperties: true,
      withPhoto: false,
    );

    if (!mounted) return;

    if (contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No contacts found on phone')),
      );
      return;
    }

    // Show picker dialog
    final selected = await showDialog<List<Contact>>(
      context: context,
      builder: (ctx) => _PhoneContactPicker(contacts: contacts),
    );

    if (selected == null || selected.isEmpty) return;

    int added = 0;
    for (final contact in selected) {
      final phone = contact.phones.isNotEmpty
          ? _normalizePhone(contact.phones.first.number)
          : '';
      if (phone.isEmpty) continue;

      final result = await ApiService.addContact(
        name: contact.displayName,
        phone: phone,
      );
      if (result.success) added++;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$added contact${added == 1 ? '' : 's'} imported'),
        backgroundColor: Colors.green,
      ),
    );
    _loadContacts();
  }

  void _showAddContactForm() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final telegramCtrl = TextEditingController();
    final relationCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Emergency Contact'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number *',
                    prefixIcon: Icon(Icons.phone),
                    hintText: '+91XXXXXXXXXX',
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    final normalized = _normalizePhone(v.trim());
                    final digits = normalized.replaceAll(RegExp(r'[^0-9]'), '');
                    if (digits.length < 10) return 'Enter a valid phone';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: telegramCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Telegram Chat ID',
                    prefixIcon: Icon(Icons.telegram),
                    hintText: 'Optional',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: relationCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Relationship',
                    prefixIcon: Icon(Icons.group),
                    hintText: 'e.g. Father, Mother, Friend',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              Navigator.pop(ctx);

              final result = await ApiService.addContact(
                name: nameCtrl.text.trim(),
                phone: _normalizePhone(phoneCtrl.text.trim()),
                telegramId: telegramCtrl.text.trim().isNotEmpty
                    ? telegramCtrl.text.trim()
                    : null,
                relationship: relationCtrl.text.trim().isNotEmpty
                    ? relationCtrl.text.trim()
                    : null,
              );

              if (!mounted) return;
              if (result.success) {
                _loadContacts();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Contact added'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result.error ?? 'Failed to add contact'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency Contacts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddOptions,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Contact'),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A212B), Color(0xFF0F1318), Color(0xFF1E171E)],
          ),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _contacts.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.contacts, size: 80, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    const Text(
                      'No emergency contacts yet',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Add contacts who will be notified\nwhen an accident is detected.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _loadContacts,
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 80),
                  itemCount: _contacts.length,
                  itemBuilder: (_, i) {
                    final c = _contacts[i];
                    final name = c['name'] as String? ?? 'Unknown';
                    final phone = c['phone'] as String? ?? '—';
                    final telegramId = c['telegram_id'] as String?;
                    final relationship = c['relationship'] as String?;

                    return GlassCard(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const CircleAvatar(
                                radius: 22,
                                backgroundColor: Color(0xFFD7263D),
                                child: Icon(
                                  Icons.people_alt_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Edit',
                                onPressed: () => _editContact(c),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                onPressed: () => _deleteContact(c['id'] as int),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              children: [
                                _detailBlock(
                                  context,
                                  icon: Icons.phone_outlined,
                                  header: 'Phone',
                                  value: phone,
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Divider(height: 1),
                                ),
                                _detailBlock(
                                  context,
                                  icon: Icons.telegram,
                                  header: 'Telegram ID',
                                  value:
                                      (telegramId != null &&
                                          telegramId.isNotEmpty)
                                      ? telegramId
                                      : 'Not set',
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Divider(height: 1),
                                ),
                                _detailBlock(
                                  context,
                                  icon: Icons.group_outlined,
                                  header: 'Relationship',
                                  value:
                                      (relationship != null &&
                                          relationship.isNotEmpty)
                                      ? relationship
                                      : 'Not set',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }

  Widget _detailBlock(
    BuildContext context, {
    required IconData icon,
    required String header,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 20,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                header,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Multi-select phone contact picker dialog
class _PhoneContactPicker extends StatefulWidget {
  final List<Contact> contacts;
  const _PhoneContactPicker({required this.contacts});

  @override
  State<_PhoneContactPicker> createState() => _PhoneContactPickerState();
}

class _PhoneContactPickerState extends State<_PhoneContactPicker> {
  final Set<int> _selected = {};
  String _search = '';

  List<Contact> get _filtered {
    if (_search.isEmpty) return widget.contacts;
    final q = _search.toLowerCase();
    return widget.contacts
        .where((c) => c.displayName.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return AlertDialog(
      title: const Text('Select Contacts'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search contacts...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final c = filtered[i];
                  final idx = widget.contacts.indexOf(c);
                  final phone = c.phones.isNotEmpty
                      ? c.phones.first.number
                      : 'No phone';
                  return CheckboxListTile(
                    value: _selected.contains(idx),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(idx);
                        } else {
                          _selected.remove(idx);
                        }
                      });
                    },
                    title: Text(c.displayName),
                    subtitle: Text(phone),
                    dense: true,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () {
                  final picks = _selected
                      .map((i) => widget.contacts[i])
                      .toList();
                  Navigator.pop(context, picks);
                },
          child: Text('Import (${_selected.length})'),
        ),
      ],
    );
  }
}
