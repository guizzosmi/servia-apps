// Firebase no iPhone (guia 66, etapa 7): valores do GoogleService-Info.plist do app "ServPilot iPhone"
// (projeto servia-ccdda). A apiKey do Firebase é de cliente (vai dentro do app, como a do Android);
// quem protege os dados são as regras do Supabase, não ela.
// ignore_for_file: unnecessary_nullable_for_final_variable_declarations
import 'package:firebase_core/firebase_core.dart';

const FirebaseOptions? opcoesFirebaseIos = FirebaseOptions(
  apiKey: 'AIzaSyDIrdJHho0v1Ja72rSoXdwrIP3SQAsxAi0',
  appId: '1:904603233185:ios:e21679ec0b891bcead39e0',
  messagingSenderId: '904603233185',
  projectId: 'servia-ccdda',
  storageBucket: 'servia-ccdda.firebasestorage.app',
  iosBundleId: 'br.com.servpilot.app',
);
