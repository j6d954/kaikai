import 'package:flutter/foundation.dart';

const bool _adminUiFlag = bool.fromEnvironment(
  'ADMIN_UI_ENABLED',
  defaultValue: false,
);

bool get isAdminUiEnabled => kDebugMode || _adminUiFlag;
