import 'package:flutter/material.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/expressive_elements.dart';
import 'package:keqdroid/shared/ui/expressive_group.dart';

class EditorLayer {
  const EditorLayer(this.icon, this.title, this.children);

  final IconData icon;
  final String title;
  final List<Widget> children;
}

// слои одной группой: путь от сервера к транспорту читается сверху вниз.
// внутри нужен Material: SwitchListTile рисует чернила на ближайшем Material-предке, его даёт ExpressiveGroupTile
class EditorLayers extends StatelessWidget {
  const EditorLayers(this.layers, {super.key});

  final List<EditorLayer> layers;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ExpressiveGroup(
      children: [
        for (final layer in layers)
          ExpressiveGroupTile(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      ExpressiveIconBadge(
                        icon: layer.icon,
                        size: 32,
                        iconSize: 18,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          layer.title,
                          style: textTheme
                              .emphasized(textTheme.titleSmall)
                              ?.copyWith(color: AppTheme.text(context)),
                        ),
                      ),
                    ],
                  ),
                ),
                ...layer.children,
              ],
            ),
          ),
      ],
    );
  }
}
