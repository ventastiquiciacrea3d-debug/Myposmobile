import 'package:objectbox/objectbox.dart';

/// Diccionario de Marcas
/// Total estimado: ~2KB para 50 marcas
@Entity()
class BrandDictionary {
  @Id()
  int id = 0;

  @Index()
  @Unique()
  String name; // Samsung, Apple, etc.

  String? logoFilename; // samsung.webp

  BrandDictionary({
    this.id = 0,
    required this.name,
    this.logoFilename,
  });
}

/// Diccionario de Atributos
/// Total estimado: ~500 bytes para 30 atributos
@Entity()
class AttributeDictionary {
  @Id()
  int id = 0;

  @Index()
  @Unique()
  String name; // Color, Talla, Capacidad, etc.

  AttributeDictionary({
    this.id = 0,
    required this.name,
  });
}

/// Diccionario de Valores de Atributos
/// Total estimado: ~3KB para 200 valores
@Entity()
class AttributeValueDictionary {
  @Id()
  int id = 0;

  @Index()
  int attributeId; // FK a AttributeDictionary

  String value; // Rojo, Azul, 32GB, etc.

  AttributeValueDictionary({
    this.id = 0,
    required this.attributeId,
    required this.value,
  });
}

/// Diccionario de Categorías
/// Total estimado: ~1KB para 50 categorías
@Entity()
class CategoryDictionary {
  @Id()
  int id = 0;

  @Index()
  @Unique()
  String name; // Electrónica, Ropa, Accesorios, etc.

  String? slug; // electronica, ropa, accesorios

  CategoryDictionary({
    this.id = 0,
    required this.name,
    this.slug,
  });
}
