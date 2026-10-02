import 'package:flutter/widgets.dart';

/// Margem das telas do painel: menor no celular, para sobrar espaço.
EdgeInsets margemDaTela(BuildContext context) =>
    EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 12 : 24);
