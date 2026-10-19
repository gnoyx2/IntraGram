part of '../home_screen.dart';

mixin _HomeScreenAppBar on ConsumerState<HomeScreen> {
  PreferredSizeWidget _appBar(ColorScheme scheme) {
    final compact =
        MediaQuery.sizeOf(context).width < 480 &&
        MediaQuery.textScalerOf(context).scale(20) > 28;
    return AppBar(
      titleSpacing: AppSpacing.lg,
      toolbarHeight: AppType.toolbarHeight(context),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(kAppName, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            S.of(context).t('home.slogan'),
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        if (!compact) ...[
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: S.of(context).t('home.searchMessages'),
            onPressed: () => Navigator.of(context).push(SearchScreen.route()),
          ),
          IconButton(
            icon: const Icon(Icons.add_link),
            tooltip: S.of(context).t('home.connectByIp'),
            onPressed: () => manualConnect(context, ref),
          ),
          if (canScanQr)
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: S.of(context).t('home.scanDevice'),
              onPressed: () => scanConnect(context, ref),
            ),
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            tooltip: S.of(context).t('home.guestPortal'),
            onPressed: () => PortalSheet.show(context),
          ),
        ],
        // 큰 글씨에서도 제목을 축소하지 않고 같은 액션을 메뉴로 옮김.
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: S.of(context).t('chat.more'),
          onSelected: (value) {
            switch (value) {
              case 'search':
                Navigator.of(context).push(SearchScreen.route());
              case 'connect':
                manualConnect(context, ref);
              case 'scan':
                scanConnect(context, ref);
              case 'portal':
                PortalSheet.show(context);
              case 'settings':
                Navigator.of(context).push(SettingsScreen.route());
              case 'wipe':
                panicWipe(context, ref);
            }
          },
          itemBuilder: (menuContext) => [
            if (compact) ...[
              PopupMenuItem(
                value: 'search',
                child: Text(S.of(context).t('home.searchMessages')),
              ),
              PopupMenuItem(
                value: 'connect',
                child: Text(S.of(context).t('home.connectByIp')),
              ),
              if (canScanQr)
                PopupMenuItem(
                  value: 'scan',
                  child: Text(S.of(context).t('home.scanDevice')),
                ),
              PopupMenuItem(
                value: 'portal',
                child: Text(S.of(context).t('home.guestPortal')),
              ),
            ],
            PopupMenuItem(
              value: 'settings',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.settings_outlined),
                title: Text(S.of(context).t('home.settings')),
              ),
            ),
            PopupMenuItem(
              value: 'wipe',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_forever, color: scheme.error),
                title: Text(
                  S.of(context).t('home.panicWipe'),
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
