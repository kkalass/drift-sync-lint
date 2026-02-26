import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

PluginBase createPlugin() => _DriftSyncLintPlugin();

class _DriftSyncLintPlugin extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => [
    //MyCustomLintCode(),
    DirectDriftWriteRule(),
  ];
}

class MyCustomLintCode extends DartLintRule {
  MyCustomLintCode() : super(code: _code);

  /// Metadata about the warning that will show-up in the IDE.
  /// This is used for `// ignore: code` and enabling/disabling the lint
  static const _code = LintCode(
    name: 'my_custom_lint_code',
    problemMessage: 'This is the description of our custom lint',
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    // Our lint will highlight all variable declarations with our custom warning.
    context.registry.addVariableDeclaration((node) {
      // "node" exposes metadata about the variable declaration. We could
      // check "node" to show the lint only in some conditions.

      // This line tells custom_lint to render a warning at the location of "node".
      // And the warning shown will use our `code` variable defined above as description.
      reporter.atNode(node, code);
    });
  }
}

class DirectDriftWriteRule extends DartLintRule {
  DirectDriftWriteRule() : super(code: _code) {
    //print('DirectDriftWriteRule initialized');
  }

  static const _code = LintCode(
    name: 'direct_drift_write',
    problemMessage:
        'Direct Drift writes are not allowed. Use the sync engine instead.',
  );

  @override
  void run(CustomLintResolver resolver, reporter, CustomLintContext context) {
    //print('Running DirectDriftWriteRule');
    context.registry.addMethodInvocation((node) {
      final methodName = node.methodName.name;
      final targetType = node.realTarget?.staticType;
      //print(
      //  'addMethodInvocation: $methodName on type ${targetType?.getDisplayString()}',
      //);
      // Check for write methods on Drift statement types
      if (_isWriteMethod(methodName, targetType)) {
        reporter.atNode(node, _code);
        return;
      }

      // Check for helper methods that return write statements
      if (_isStatementHelperMethod(methodName, node.methodName.element)) {
        reporter.atNode(node, _code);
        return;
      }

      // Check for batch operations
      if (methodName == 'batch' &&
          _isFromDriftPackage(node.methodName.element)) {
        reporter.atNode(node, _code);
        return;
      }
    });
  }

  /// Returns true if [element] is declared inside the `drift` package.
  bool _isFromDriftPackage(Element? element) {
    final uri = element?.library?.uri;
    return uri?.scheme == 'package' &&
        (uri?.pathSegments.firstOrNull == 'drift' ||
            uri?.pathSegments.firstOrNull == 'drift_dev');
  }

  bool _isWriteMethod(String methodName, DartType? targetType) {
    if (targetType == null) return false;

    // The type names are Drift-specific enough that a name check suffices;
    // element3 gives us Element2 so we can also verify the package origin.
    final typeElement = targetType.element;
    if (typeElement == null) return false;
    if (!_isFromDriftPackage(typeElement)) return false;

    final typeName = typeElement.name;

    // Write methods on statement types
    const writeStatementTypes = {
      'InsertStatement',
      'UpdateStatement',
      'DeleteStatement',
      'Batch',
    };

    if (writeStatementTypes.contains(typeName)) {
      // Methods that execute writes
      const writeMethods = {
        'insert',
        'insertOnConflictUpdate',
        'insertAll',
        'write',
        'writeNullable',
        'go',
      };
      return writeMethods.contains(methodName);
    }

    return false;
  }

  bool _isStatementHelperMethod(String methodName, Element? element) {
    // Only flag methods actually declared in the drift package to avoid
    // false positives on identically-named methods in other classes.
    if (!_isFromDriftPackage(element)) return false;

    // Methods that create write statements
    const helperMethods = {
      'into', // returns InsertStatement
      'update', // returns UpdateStatement
      'delete', // returns DeleteStatement
      'customStatement',
      'customInsert',
      'customUpdate',
    };
    return helperMethods.contains(methodName);
  }
}
