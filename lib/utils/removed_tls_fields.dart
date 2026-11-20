// allowInsecure ядро снесло насмерть: одного такого поля в готовом конфиге хватает, чтобы упал весь
library;

const _removedTlsKeys = {'allowInsecure'};

// по всему дереву: поле встречается и в запасных инбаундах, и внутри цепочек
int stripRemovedTlsFields(Object? config) {
  var dropped = 0;

  void walk(Object? node) {
    if (node is Map) {
      for (final key in _removedTlsKeys) {
        if (node.remove(key) != null) dropped++;
      }
      for (final value in node.values.toList()) {
        walk(value);
      }
    } else if (node is List) {
      for (final value in node) {
        walk(value);
      }
    }
  }

  walk(config);
  return dropped;
}
