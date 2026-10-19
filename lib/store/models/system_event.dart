part of '../models.dart';

@immutable
class SystemEvent {
  const SystemEvent(this.kind, [this.alias]);

  final SystemEventKind kind;
  final String? alias;

  @override
  bool operator ==(Object other) =>
      other is SystemEvent && other.kind == kind && other.alias == alias;

  @override
  int get hashCode => Object.hash(kind, alias);
}
