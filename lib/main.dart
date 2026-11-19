import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';


part 'src/app_support.dart';
part 'src/config_parser.dart';
part 'src/server_models.dart';
part 'src/app_root.dart';
part 'src/main_shell.dart';
part 'src/onboarding.dart';
