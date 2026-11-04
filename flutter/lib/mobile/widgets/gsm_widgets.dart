import 'package:flutter/material.dart';
import 'package:settings_ui/settings_ui.dart';

import '../../common.dart';

/// GSMDesk: a bordered card, the main building block of the phone screens, as
/// in the desktop window.
class GsmCard extends StatelessWidget {
  const GsmCard({
    Key? key,
    required this.child,
    this.margin = const EdgeInsets.fromLTRB(12, 10, 12, 0),
    this.padding = const EdgeInsets.all(14),
    this.borderColor,
  }) : super(key: key);

  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: MyTheme.gsmCard(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor ?? MyTheme.gsmLine(context)),
      ),
      child: child,
    );
  }
}

/// GSMDesk: small uppercase title of a card, with an optional icon.
class GsmSectionLabel extends StatelessWidget {
  const GsmSectionLabel(this.text, {Key? key, this.icon}) : super(key: key);

  final String text;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final color = MyTheme.gsmMuted(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if (icon != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: IconTheme.merge(
                data: IconThemeData(size: 15, color: color),
                child: icon!,
              ),
            ),
          Expanded(
            child: Text(
              text.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// GSMDesk: colours of the settings lists, for both themes.
SettingsThemeData gsmSettingsTheme(BuildContext context) {
  final muted = MyTheme.gsmMuted(context);
  return SettingsThemeData(
    settingsListBackground: Theme.of(context).scaffoldBackgroundColor,
    settingsSectionBackground: MyTheme.gsmCard(context),
    titleTextColor: MyTheme.gsmSignal(context),
    settingsTileTextColor: Theme.of(context).textTheme.bodyMedium?.color,
    tileDescriptionTextColor: muted,
    trailingTextColor: muted,
    leadingIconsColor: muted,
    dividerColor: MyTheme.gsmLine(context),
    tileHighlightColor: MyTheme.gsmLine(context),
  );
}
