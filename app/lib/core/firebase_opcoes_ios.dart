// Firebase no iPhone (guia 66). Fica null até o app do iPhone existir no Firebase:
// quando você salvar o GoogleService-Info.plist em app/ios/Runner, o Claude preenche
// os valores aqui e liga as notificações do iPhone (entitlements com o aps-environment).
// ignore_for_file: unnecessary_nullable_for_final_variable_declarations
import 'package:firebase_core/firebase_core.dart';

const FirebaseOptions? opcoesFirebaseIos = null;
