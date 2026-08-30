class OfflineDemoUser {
  const OfflineDemoUser({
    required this.userId,
    required this.companyId,
    required this.name,
    required this.password,
    required this.licenseType,
    required this.isPermanent,
  });

  final int userId;
  final int companyId;
  final String name;
  final String password;
  final String licenseType;
  final bool isPermanent;
}

class OfflineDemoData {
  static const Map<String, OfflineDemoUser> accounts = {
    '1000000003': OfflineDemoUser(
      userId: 3,
      companyId: 1,
      name: 'Yesenia López',
      password: 'yesy2001',
      licenseType: 'permanent',
      isPermanent: true,
    ),
    '1000000002': OfflineDemoUser(
      userId: 2,
      companyId: 1,
      name: 'Prueba Usuario',
      password: 'prueba2026',
      licenseType: 'permanent',
      isPermanent: true,
    ),
  };

  static const Map<int, List<Map<String, dynamic>>> catalogsByUser = {
    3: [
      {'id': 101, 'code': 'P-1001', 'name': 'Café Americano', 'price': 38.0, 'stock': 120.0},
      {'id': 102, 'code': 'P-1002', 'name': 'Té Verde', 'price': 32.0, 'stock': 95.0},
      {'id': 103, 'code': 'P-1003', 'name': 'Sándwich Club', 'price': 120.0, 'stock': 60.0},
      {'id': 104, 'code': 'P-1004', 'name': 'Refresco Cola', 'price': 28.0, 'stock': 180.0},
      {'id': 105, 'code': 'P-1005', 'name': 'Agua Mineral', 'price': 22.0, 'stock': 200.0},
      {'id': 106, 'code': 'P-1006', 'name': 'Tostadas de Frijol', 'price': 65.0, 'stock': 85.0},
      {'id': 107, 'code': 'P-1007', 'name': 'Pastel de Chocolate', 'price': 75.0, 'stock': 70.0},
      {'id': 108, 'code': 'P-1008', 'name': 'Helado Vainilla', 'price': 58.0, 'stock': 110.0},
    ],
    2: [
      {'id': 201, 'code': 'P-2001', 'name': 'Papas Fritas', 'price': 52.0, 'stock': 140.0},
      {'id': 202, 'code': 'P-2002', 'name': 'Hamburguesa Doble', 'price': 165.0, 'stock': 75.0},
      {'id': 203, 'code': 'P-2003', 'name': 'Hot Dog', 'price': 88.0, 'stock': 90.0},
      {'id': 204, 'code': 'P-2004', 'name': 'Galletas', 'price': 35.0, 'stock': 200.0},
      {'id': 205, 'code': 'P-2005', 'name': 'Jugo de Naranja', 'price': 42.0, 'stock': 130.0},
      {'id': 206, 'code': 'P-2006', 'name': 'Ensalada César', 'price': 140.0, 'stock': 55.0},
      {'id': 207, 'code': 'P-2007', 'name': 'Brownie', 'price': 68.0, 'stock': 80.0},
      {'id': 208, 'code': 'P-2008', 'name': 'Smoothie Fresa', 'price': 78.0, 'stock': 65.0},
    ],
  };

  static bool isOfflineDemoUser(String identifier, String password) {
    final user = accounts[identifier];
    return user != null && user.password == password;
  }

  static OfflineDemoUser? userForIdentifier(String identifier) {
    return accounts[identifier];
  }

  static List<Map<String, dynamic>> catalogForUser(int userId) {
    return [...?catalogsByUser[userId]];
  }

  static Map<String, dynamic> loginPayloadFor(String identifier) {
    final user = accounts[identifier];
    if (user == null) {
      throw StateError('Usuario demo no encontrado');
    }

    return {
      'token': 'offline-demo-token-${user.userId}',
      'user': {
        'id': user.userId,
        'name': user.name,
        'username': user.name,
      },
      'empresa': {
        'id': user.companyId,
        'empresa_id': user.companyId,
        'name': 'Demo Company',
      },
      'licencia': {
        'tipo': user.licenseType,
        'vigente': true,
        'permanente': user.isPermanent,
      },
    };
  }
}
