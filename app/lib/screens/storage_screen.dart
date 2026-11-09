import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../widgets/scaffold.dart';

/// Storage. What the app keeps on this device and how much room each kind
/// takes. Everything listed is counted from the device itself when the
/// page opens. Nothing here is kept anywhere else.
class StorageScreen extends StatelessWidget {
  const StorageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final storage = state.storage;
    final rows = [
      (
        AppIcons.chat,
        l10n.storageChats,
        l10n.storageChatsDetail,
        formatBytes(storage.storeBytes),
      ),
      (
        AppIcons.file,
        l10n.storageReceived,
        l10n.storageReceivedDetail,
        l10n.storageFilesAndSize(
          storage.receivedFiles,
          formatBytes(storage.receivedBytes),
        ),
      ),
      (
        AppIcons.mic,
        l10n.storageVoice,
        l10n.storageVoiceDetail,
        l10n.storageFilesAndSize(
          storage.voiceFiles,
          formatBytes(storage.voiceBytes),
        ),
      ),
      (
        AppIcons.nearby,
        l10n.storageCarried,
        l10n.storageCarriedDetail,
        l10n.storageMessagesAndSize(
          storage.carriedMessages,
          formatBytes(storage.carriedBytes),
        ),
      ),
    ];

    return AppScreen(
      header: AppTopBar(title: l10n.storage),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatBytes(storage.total),
                  style: AppText.base.copyWith(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.storageWhere(context.deviceKind),
                  style: AppText.detail,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (index, (icon, title, detail, value))
                    in rows.indexed) ...[
                  if (index > 0) Container(height: 1, color: AppColors.line),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppIcon(icon, size: 20, color: AppColors.text2),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: AppText.rowTitle),
                              const SizedBox(height: 2),
                              Text(detail, style: AppText.detail),
                              const SizedBox(height: 4),
                              Text(
                                value,
                                style: AppText.detail.copyWith(
                                  color: AppColors.text,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(l10n.storageHowToClear, style: AppText.detail),
          ),
        ],
      ),
    );
  }
}
