part of '../settings_tab.dart';

// ignore: unused_element
class _SplitTunnelingScreen extends ConsumerWidget {
  const _SplitTunnelingScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appsAsync = ref.watch(installedAppsProvider(false));
    final splitState = ref.watch(splitTunnelingProvider);

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.bg(context),
        title: Text('Split Tunneling', style: TextStyle(color: AppTheme.text(context))),
        iconTheme: IconThemeData(color: AppTheme.text(context)),
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () => ref.read(splitTunnelingProvider.notifier).clearAll(),
            child: Text('Clear all', style: TextStyle(color: AppTheme.textLight(context))),
          ),
        ],
      ),
      body: appsAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: AppTheme.accent(context))),
        error: (e, _) => Center(child: Text('Error loading apps: $e')),
        data: (apps) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                '${splitState.excludePackages.length} apps bypass VPN',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textLight(context)),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: apps.length,
                itemBuilder: (_, i) {
                  final app = apps[i];
                  final excluded = splitState.excludePackages.contains(app.packageName);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.card(context),
                      child: Text(app.appName[0], style: TextStyle(color: AppTheme.text(context))),
                    ),
                    title: Text(app.appName, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.text(context))),
                    subtitle: Text(
                      app.packageName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textLight(context)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Switch(
                      value: excluded,
                      activeThumbColor: AppTheme.accent(context),
                      onChanged: (_) => ref.read(splitTunnelingProvider.notifier).toggleExclude(app.packageName),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

