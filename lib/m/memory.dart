/*
Copyright (c) 2021,2022 William Foote

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 3 of the License, or (at your option) any later
version.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

You should have received a copy of the GNU General Public License along with
this program; if not, see https://www.gnu.org/licenses/ .
*/
part of 'model.dart';

/// The calculator's 406 nybble internal memory that holds registers and
/// programs.
class Memory<OT extends ProgramOperation> {
  final ByteData _storage = ByteData(406);
  //  We hold one nybble (4 bits) in each byte of _storage.  The program
  // isn't stored here, but we do zero out that part of storage when
  // program lines are added, to simulate the behavior of shared storage.
  late final ProgramMemory<OT> program;
  late final registers = Registers(this);

  final Model<OT> _model;

  Memory(this._model);

  int get _programNybbles => program.programBytes * 2;

  /// Called by our controller, which necessarily happens after the Model
  /// exists.
  void initializeSystem(OperationMap<OT> layout) {
    program = ProgramMemory<OT>(this, _storage,
        layout._operationTable, _model.returnStackSize);

    // We rely on our Controller to give us an OperationMap with the
    // layout information that tells us the row/column positions of the various
    // operations.  Those positions are how the 16C displays program
    // instructions, and it's also how we externalize them in our JSON
    // state file.
    //
    // We don't need to retain the layout, but we do need to ensure that
    // one is created.  The OperationMap constructor has the side effect
    // of initializing late final fields that we depend on.  Admittedly, this
    // is a little tricky - making initialization happen while keeping modules
    // decoupled sometimes is.
  }

  void reset() {
    for (int i = 0; i < _storage.lengthInBytes; i++) {
      _storage.setUint8(i, 0);
    }
    program.reset(zeroMemory: false);
    registers.resetI();
  }

  Map<String, Object> toJson({bool comments = false}) {
    final st = StringBuffer();
    for (int i = 0; i < _storage.lengthInBytes; i++) {
      st.write(_storage.getUint8(i).toRadixString(16));
    }
    final r = <String, Object>{
      'storage': st.toString(),
      'program': program,
      'I': registers._indexValue.toJson()
    };
    if (comments) {
      r['commentProgramListing'] = program.listing;
    }
    return r;
  }

  void decodeJson(Map<String, dynamic> json) {
    final sto = json['storage'] as String;
    for (int i = 0; i < _storage.lengthInBytes; i++) {
      _storage.setUint8(i, int.parse(sto.substring(i, i + 1), radix: 16));
    }
    // Must come after storage.  cf. ProgramMemory.decodeJson().
    program.decodeJson(json['program'] as Map<String, dynamic>);
    registers._indexValue =
        Value.fromJson(json['I'] as String, maxInternal: Registers._maxI);
  }
}

/// A helper for the index register, which is always stored as a 68 bit
/// quantity, regardless of the calculator mode.
class _NumStatus68 implements NumStatus {
  final Model _model; // For the sign mode

  _NumStatus68(this._model);

  @override
  bool cFlag = false;

  @override
  bool gFlag = false;

  @override
  int get wordSize => 68;

  @override
  final BigInt wordMask = (BigInt.one << 68) - BigInt.one;

  @override
  final BigInt signMask = (BigInt.one << 67);

  @override
  BigInt get maxInt => _model._integerSignMode.maxValue(this);

  @override
  BigInt get minInt => _model._integerSignMode.minValue(this);

  @override
  bool get isFloatMode => _model.isFloatMode;

  @override
  IntegerSignMode get integerSignMode => _model.integerSignMode;

  Value signExtendFrom(Value other) {
    if (!_model.signMode.doesSignExtension) {
      return other;
    }
    BigInt internal = other.internal;
    if (BigInt.zero == internal & _model.signMask) {
      return other;
    }
    BigInt bitToSet = _model.signMask << 1;
    while (bitToSet <= signMask) {
      internal = internal | bitToSet;
      bitToSet <<= 1;
    }
    return Value.fromInternal(internal);
  }
}

///
/// A representation of the available memory as registers.  "Available memory"
/// is what's left over of the 406 nybble data store after the program's
/// storage is deducted.
///
class Registers {
  final Memory _memory;
  // A helper for dealing with 68 bit values, like I
  final _NumStatus68 helper68;

  /// Value of the index register, I, always stored in 68 bits.
  Value _indexValue = Value.zero;

  Registers(this._memory) : helper68 = _NumStatus68(_memory._model);

  static final BigInt _maxI = BigInt.parse('fffffffffffffffff', radix: 16);
  // 16^17-1, that is, 2^68-1

  Model get _model => _memory._model;

  int get _nybblesPerRegister => (_model.wordSize + 3) ~/ 4;

  int get length =>
      (_memory._storage.lengthInBytes - _memory._programNybbles) ~/
      _nybblesPerRegister;

  static final BigInt _oneKmask = BigInt.from(0x3ff);

  Value operator [](int i) {
    if (i < 0 || i >= length) {
      throw CalculatorError(3);
    }
    final int npr = _nybblesPerRegister;
    int addr = _memory._storage.lengthInBytes - 1 - (i + 1) * npr;
    // Address of most significant nybble - 1
    BigInt value = BigInt.zero;
    for (int i = 0; i < npr; i++) {
      value = (value << 4) | BigInt.from(_memory._storage.getUint8(++addr));
    }
    final result = Value.fromInternal(value);
    if (_model.isFloatMode) {
      result.asDouble; // Throw exception if not valid float
    }
    return result;
  }

  static final BigInt _low4 = BigInt.from(0xf);

  void operator []=(int i, Value v) {
    if (i < 0 || i >= length) {
      throw CalculatorError(3);
    }
    final int npr = _nybblesPerRegister;
    BigInt value = v.internal;
    int addr = _memory._storage.lengthInBytes - 1 - i * npr;
    // Address of least significant nybble
    for (int i = 0; i < npr; i++) {
      _memory._storage.setUint8(addr--, (value & _low4).toInt());
      value >>= 4;
    }
    _model._needsSave = true;
  }

  Value get index {
    final result = Value.fromInternal(_indexValue.internal & _model.wordMask);
    if (_model.isFloatMode) {
      result.asDouble; // Throw exception if not valid float
    }
    return result;
  }

  set index(Value v) => _indexValue = helper68.signExtendFrom(v);

  Value get indirectIndex => this[_regIasIndex];
  set indirectIndex(Value v) => this[_regIasIndex] = v;

  Value getValue(int i, ProgramOperationArg arg) {
    if (i == arg.desc.indexRegisterNumber) {
      return index;
    } else if (i == arg.desc.indirectIndexNumber) {
      return indirectIndex;
    } else {
      return this[i - arg.desc.r0ArgumentValue];
    }
  }

  void setValue(int i, ProgramOperationArg arg, Value v) {
    if (i == arg.desc.indexRegisterNumber) {
      index = v;
    } else if (i == arg.desc.indirectIndexNumber) {
      indirectIndex = v;
    } else {
      this[i - arg.desc.r0ArgumentValue] = v;
    }
  }

  /// Calculate the value of the I register for use as an index.  If that
  /// value is too big to be an index, then any int that is too big will do,
  /// since we'll just end up generating a CalculatorError anyway.
  int get _regIasIndex {
    if (_model.isFloatMode) {
      Value masked = Value.fromInternal(_indexValue.internal & _model.wordMask);
      double d = masked.asDouble.abs();
      if (d > 1000) {
        return 1000; // close enough to infinity
      } else {
        return d.floor();
      }
    } else {
      BigInt bi = _model._integerSignMode.toBigInt(_indexValue, helper68).abs();
      if (bi > _oneKmask) {
        return 1024; // close enough to infinity
      } else {
        return bi.toInt().abs();
      }
    }
  }

  void resetI() {
    _indexValue = Value.zero;
  }

  void clear() {
    resetI();
    final maxMem = _memory._storage.lengthInBytes;
    for (int addr = _memory._programNybbles; addr < maxMem; addr++) {
      _memory._storage.setUint8(addr, 0);
    }
  }

  bool isZeroI(Value v) => _model.signMode.isZero(helper68, v);

  /// Gives value after increment
  Value incrementI(int by) {
    return _indexValue = _model.signMode.increment(helper68, _indexValue, by);
  }
}

///
/// A representation of the calculator's 406 nybble data store as a list
/// of program instructions.  ProgramMemory takes over space from register
/// storage as needed.  We also keep the return stack for GSB instructions
/// here, and the current program line.
///
/// ProgramMemory takes care of the 15C's two-byte program instructions
/// (cf. 15C manual page 218).  For example, if line 3 is F-ENG-2, the next
/// line will be line 4, despite the fact that F-ENG-2 takes up two bytes.
///
class ProgramMemory<OT extends ProgramOperation> {
  final Memory<OT> _memory;

  /// Indexed by opCode
  final List<OT?> _operationTable;

  int _lines = 0;
  // Number of lines with extended op codes
  int _extendedLines = 0;

  final List<int> _returnStack;
  int _returnStackPos = -1;

  /// Current line (editing and/or execution)
  int _currentLine = 0;

  /// opcodeAt(line) caches a line # and a corresponding address, since calculating
  /// the address would be O(n), given multibyte instructions.
  int _cachedLine = 1;

  /// Line 1 is stored starting at address 0
  int _cachedAddress = 0;

  /// This is a testing hook; tests can override this to tweak behaviors
  /// and detect events.
  ProgramListener programListener = ProgramListener();

  ProgramMemory(this._memory, this._registerStorage,
      this._operationTable, int returnStackSize)
      : _returnStack = List.filled(returnStackSize, 0);

  final ByteData _registerStorage;

  int get programBytes => ((_lines + _extendedLines + 6) ~/ 7) * 7;

  int get _maxAddress => (_lines + _extendedLines) * 2 - 1;

  /// Number of lines in the program
  int get lines => _lines;

  int get currentLine => _currentLine;

  int get bytesToNextAllocation =>
      (_registerStorage.lengthInBytes ~/ 2 - _lines - _extendedLines) % 7;

  set currentLine(int v) {
    if (v < 0 || v > lines) {
      throw CalculatorError(4);
    }
    _currentLine = v;
  }

  /// Insert a new instruction, and increment currentLine to refer to it.
  void insert(final ProgramInstruction<OT> instruction) {
    final needed = instruction.isExtended ? 2 : 1;
    if (_lines + _extendedLines + needed >
        _registerStorage.lengthInBytes ~/ 2) {
      throw CalculatorError(4);
    }
    assert(_currentLine >= 0 && _currentLine <= _lines);
    assert(instruction.argValue >= 0 &&
        instruction.argValue <= instruction.op.maxArg);
    _setCachedAddress(_currentLine + 1);
    int addr = _cachedAddress; // stored as nybbles
    for (int a = _maxAddress; a >= addr; a--) {
      _registerStorage.setUint8(a + 2 * needed, _registerStorage.getUint8(a));
    }
    final int opCode = instruction.opCode;
    assert(opCode >= 0 && opCode <= 0x1ff);
    if (opCode & 0x100 != 0) {
      _registerStorage.setUint8(addr++, 0xf);
      _registerStorage.setUint8(addr++, 0xf);
      _extendedLines++;
    }
    _registerStorage.setUint8(addr++, (opCode >> 4) & 0xf);
    _registerStorage.setUint8(addr++, opCode & 0xf);
    _lines++;
    _currentLine++; // Where we just inserted the instruction

    _memory._model._needsSave = true;
  }

  void deleteCurrent() {
    assert(_lines > 0 && _currentLine > 0);
    final op = opcodeAt(_currentLine); // Sets _cachedAddress
    final extended = op >= 0x100;
    int addr = _cachedAddress;
    _lines--;
    _currentLine--;
    final int delta;
    if (extended) {
      _extendedLines--;
      delta = 4;
    } else {
      delta = 2;
    }
    while (addr <= _maxAddress) {
      _registerStorage.setUint8(addr, _registerStorage.getUint8(addr + delta));
      addr++;
    }
    if (extended) {
      _registerStorage.setUint8(addr++, 0);
      _registerStorage.setUint8(addr++, 0);
    }
    _registerStorage.setUint8(addr++, 0);
    _registerStorage.setUint8(addr, 0);

    _memory._model._needsSave = true;
  }

  /// line counts from 1
  ProgramInstruction<OT> operator [](final int line) {
    final int opCode = opcodeAt(line);
    final OT op = _operationTable[opCode]!;
    // throws an exception on an illegal opCode, which is what we want.
    final int arg = opCode & 0x100  != 0
        ? (opCode & 0xff) - op._extendedOpCode + op.numOpCodes
        : opCode - op._opCode;
    return _memory._model.newProgramInstruction(op, arg);
    // We're storing the instructions as nybbles and creating instructions
    // as-needed, not to save memory.  Rather, it's the easiest way of
    // implementing it, given that we want to store the program in a form
    // that is faithful to the original 16C, that preserves the memory
    // management constraints.  The extra time we spend converting back and
    // forth is, of course, irrelevant.
  }

  void _setCachedAddress(final int line) {
    if (line < _cachedLine) {
      _cachedLine = 1;
      _cachedAddress = 0;
    }
    while (_cachedLine < line) {
      _cachedLine++;
      if (_byteAt(_cachedAddress) == 0xff) {
        _cachedAddress += 4;
      } else {
        _cachedAddress += 2;
      }
    }
  }

  int opcodeAt(final int line) {
    assert(line > 0 && line <= _lines);
    _setCachedAddress(line);
    final b = _byteAt(_cachedAddress);
    if (b != 0xff) {
      return b;
    } else {
      return 0x100 | _byteAt(_cachedAddress + 2);
    }
  }

  int _byteAt(int a) =>
      (_registerStorage.getUint8(a) << 4) + _registerStorage.getUint8(a + 1);

  ProgramInstruction<OT> getCurrent() => this[currentLine];

  void reset({bool zeroMemory = true}) {
    if (zeroMemory) {
      for (int i = 0; i < _lines * 2; i++) {
        _registerStorage.setUint8(i, 0);
      }
    }
    _lines = 0;
    _currentLine = 0;
    _extendedLines = 0;
    resetReturnStack();
  }

  Map<String, dynamic> toJson() => <String, Object>{
        'lines': _lines,
        'currentLine': _currentLine,
        'returnStack': _returnStack,
        'returnStackPos': _returnStackPos
      };

  /// Must be called after the register storage has been read in, so any
  /// stray data will be propely zeroed out.
  void decodeJson(Map<String, dynamic> json) {
    int n = (json['lines'] as num).toInt();
    if (n < 0 || n > _registerStorage.lengthInBytes ~/ 2) {
      throw ArgumentError('$n:  Illegal number of lines');
    }
    _lines = n;
    _extendedLines = 0;
    // Check for illegal instructions
    try {
      for (_currentLine = 1; _currentLine <= _lines; _currentLine++) {
        final instr = getCurrent();
        if (instr.isExtended) {
          _extendedLines++;
        }
      }
      _currentLine = 0;
    } catch (e) {
      _lines = 0;
      _currentLine = 0;
      rethrow;
    }
    n = (json['currentLine'] as num).toInt();
    if (n < 0 || n > _lines) {
      throw ArgumentError('$n:  Illegal line number');
    }
    _currentLine = n;

    final returnStack = (json['returnStack'] as List<dynamic>?);
    if (returnStack != null && returnStack.length == _returnStack.length) {
      for (int i = 0; i < returnStack.length; i++) {
        _returnStack[i] = returnStack[i] as int;
      }
    }
    final returnStackPos = (json['returnStackPos'] as num?);
    if (returnStackPos != null) {
      _returnStackPos = returnStackPos.toInt();
    }
  }

  List<String> get listing {
    final r = List<String>.empty(growable: true);
    for (int i = 1; i <= lines; i++) {
      String line = i.toString().padLeft(3, '0');
      String opc = opcodeAt(i).toRadixString(16).padLeft(2, '0');
      final ProgramInstruction<OT> pi = this[i];
      String semiHuman = this[i].programDisplay.padLeft(9);
      String human = pi.programListing;
      r.add('$line --$semiHuman    0x$opc  $human');
    }
    return r;
  }

  void stepCurrentLine(int sign) {
    int line = currentLine + sign;
    if (line < 0) {
      currentLine = lines;
    } else if (line > lines) {
      currentLine = 0;
    } else {
      currentLine = line;
    }
  }

  void displayCurrent({bool flash = false, bool delayed = false}) {
    final display = _memory._model.display;
    final String newText;
    if (currentLine == 0) {
      newText = '000-      ';
    } else {
      String ls = currentLine.toRadixString(10).padLeft(3, '0');
      String disp = getCurrent().programDisplay;
      newText = '$ls-$disp';
    }
    if (delayed) {
      final initial = _memory._model._newLcdContents();
      display.current = newText;
      final delayed = _memory._model._newLcdContents();
      final t = Timer(const Duration(milliseconds: 1400), () {
        display.show(delayed);
      });
      delayed._myTimer = t;
      initial._myTimer = t;
      display.show(initial);
    } else {
      display.current = newText;
      display.update(flash: flash);
    }
  }

  void popReturnStack() {
    if (_returnStackPos > 0) {
      currentLine = _returnStack[--_returnStackPos];
    } else {
      _returnStackPos = -1;
      currentLine = 0;
    }
  }

  void gosub(int label, ArgDescription arg) {
    if (_returnStackPos >= _returnStack.length) {
      throw CalculatorError(5);
    }
    final returnTo = currentLine;
    goto(label, arg);
    if (returnStackUnderflow) {
      // Keyboard entry of GSB to start program
      _returnStackPos++;
    } else {
      _returnStack[_returnStackPos++] = returnTo;
    }
  }

  static final BigInt _fifteen = BigInt.from(15);

  void goto(int label, ArgDescription arg) {
    Value? v;
    if (label == arg.indexRegisterNumber) {
      v = _memory.registers.index;
    } else if (label == arg.indirectIndexNumber) {
      v = _memory.registers.indirectIndex;
    }
    if (v != null) {
      // I or (i)
      if (_memory._model.isFloatMode) {
        double fv = v.asDouble;
        if (fv < 0 || fv >= 16) {
          throw CalculatorError(4);
        }
        label = fv.floor();
        if (label > 16 || label < 0) {
          // This should be impossible, but I'm not 100% certain of double
          // semantics, e.g. on JavaScript.
          throw CalculatorError(4);
        }
      } else {
        BigInt iv = v.internal;
        if (iv < BigInt.zero || iv > _fifteen) {
          throw CalculatorError(4);
        }
        label = iv.toInt();
      }
    }
    int wanted = OperationMap._instance!.lbl._opCode + label;
    // We might be at the label, so we start at 0.  Also, remember that
    // line 0 has the phantom return instruction, so we have to
    // iterate over lines+1 "lines".
    if (lines != 0) {
      for (int i = 0; i <= lines; i++) {
        int line = (currentLine + i) % lines;
        if (line == 0) {
          line = lines;
        }
        if (opcodeAt(line) == wanted) {
          currentLine = line;
          return;
        }
      }
    }
    throw CalculatorError(4);
  }

  void resetReturnStack() {
    _returnStackPos = -1;
    assert(returnStackUnderflow);
  }

  bool get returnStackUnderflow => _returnStackPos < 0;

  /// A RunStop keypress can resume a program, in which case the return stack
  /// shoould be left undisturbed.  It can also start a "new" program run,
  /// so we need to be sure the return stack isn't in underflow
  void handleRunStopKepyress() {
    if (returnStackUnderflow) {
      _returnStackPos = 0;
    }
  }

  /// Increment the current line, up to a max of lines, wrapping to 0.
  /// To be clear, there are lines+1 possible values.
  ///
  /// Note that the branching instructions can cause the program to increment
  /// past the phantom RTN instruction at the end of memory, wrapping back
  /// to line 1.  This is intentional, and mirrors the behavior I observed
  /// on my 15C.
  void incrementCurrentLine() => currentLine = (currentLine + 1) % (lines + 1);

  void doNextIf(bool condition) {
    if (!condition) {
      incrementCurrentLine();
    }
  }
}

///
/// The model's view of an operation.  This is extended by the controller's
/// Operation class.  The parts of Operation that are relevant to the model
/// are lifted into the model class ProgramOperation so that Model doesn't
/// depend on a controller class.  Model is parameterized by ProgramOperation
/// so that the controller can refer to members of Operation that are logically
/// part of the controller.
///
abstract class ProgramOperation {
  late final String _programDisplay;
  late final int _opCode;
  late final int _extendedOpCode;

  ProgramOperationArg? get arg;

  /// 0 if this operation doesn't take an argument
  int get maxArg;
  String get name;

  int get numExtendedOpCodes => 0;
  int get numOpCodes => 1 + maxArg - numExtendedOpCodes;

  static const _invalidOpCodeStart = -1;
  // Invalid op codes are negative, but still distinct.  That allows them to
  // be used in the capture of a debug key log.

  String get programDisplay => _programDisplay;

  /// Give the numeric value of a number key.
  /// cf. tests.dart, SelfTests.testNumbers().
  int? get numericValue => null;

  @override
  String toString() => 'ProgramOperation($programDisplay)';
}

abstract class ProgramOperationArg {
  ArgDescription get desc;
}

///
/// Some metadata about an argument to a program operation.
///
@immutable
abstract class ArgDescription {
  const ArgDescription();

  int get indirectIndexNumber;
  int get indexRegisterNumber;
  int get maxArg;

  ///
  /// The argument value that corresponds to register 0.  On the 16C this is
  /// 0, but (i) and I need to be argument values 0 and 1 for a few operations
  /// on the 15C, so that they will be assigned single-byte opcodes.
  ///
  int get r0ArgumentValue => 0;
}

///
/// A description suitable for most of the args on the 16C
///
@immutable
class ArgDescription16C extends ArgDescription {
  @override
  final int maxArg;

  const ArgDescription16C({required this.maxArg});

  @override
  int get indirectIndexNumber => 32;
  @override
  int get indexRegisterNumber => 33; // It's to the right on the keyboard
}

@immutable
class ArgDescriptionGto16C extends ArgDescription {
  const ArgDescriptionGto16C();

  @override
  int get maxArg => 17;
  // This actually allows GSB (i) and GTO (i), which AFAIK aren't implemented
  // on a real 16c (cf. manual page 88).  Oops!  However, maxArg can't be
  // changed to 16 without chaning the opcode assignments, which would break
  // backwards compatibility.  Having this weird extension to the 16C's
  // semantics is harmless, I guess, and disabling this extension would be
  // needlessly antisocial, given that the app has been out there for a while.
  @override
  int get indirectIndexNumber => 16;
  @override
  int get indexRegisterNumber => 17; // It's to the right on the keyboard
}

@immutable
class ArgDescription15C extends ArgDescription {
  @override
  final int maxArg;

  const ArgDescription15C({required this.maxArg});

  @override
  int get indirectIndexNumber => 0;
  @override
  int get indexRegisterNumber => 1; // It's to the right on the keyboard
  @override
  int get r0ArgumentValue => 2;
}

@immutable
class ArgDescription15CJustI extends ArgDescription {
  @override
  final int maxArg;

  const ArgDescription15CJustI({required this.maxArg});

  @override
  int get indirectIndexNumber => 0xdeadbeef;
  @override
  int get indexRegisterNumber => 0; // It's to the right on the keyboard
  @override
  int get r0ArgumentValue => 1;
}

@immutable
class ArgDescriptionGto15C extends ArgDescription {
  const ArgDescriptionGto15C();

  @override
  int get maxArg => 25;
  // That's 0 to 9, .0 to .9, A-E, and I
  @override
  int get indirectIndexNumber => 0xdeadbeef;
  // The 15C doesn't allow GTO (i) or GSB (i).  Note also that the handling
  // of negative values of I is different on the 15c.
  // see 15C manual, bottom of page 108
  @override
  int get indexRegisterNumber => 25;
}

///
/// The model's view of a key on the keyboard.  The model needs to know where
/// [ProgramOperation]s are on the portrait layout of the keyboard, because
/// they are displayed on the LCD display as row-column numbers.
///
class MKey<OT extends ProgramOperation> {
  final OT unshifted;
  final OT fShifted;
  final OT gShifted;

  final List<MKeyExtensionOp<OT>> extensionOps;

  const MKey(this.unshifted, this.fShifted, this.gShifted,
      {this.extensionOps = const []});
}

@immutable
class MKeyExtensionOp<OT extends ProgramOperation> {
  final OT op;
  final String programDisplayPrefix;

  const MKeyExtensionOp(this.op, this.programDisplayPrefix);
}

///
/// An instruction in a program, consisting of a [ProgramOperation] and,
/// sometimes, an argument value.
///
abstract class ProgramInstruction<OT extends ProgramOperation> {
  OT op;

  /// 0 if no argument
  int argValue;

  ProgramInstruction(this.op, this.argValue);

  bool get isExtended => argValue > op.maxArg - op.numExtendedOpCodes;

  final _noWidth = RegExp('[,.]');

  int get opCode => isExtended
      ? (op._extendedOpCode | 0x100) + (argValue - op.numOpCodes)
      : op._opCode + argValue;

  @protected
  String rightJustify(String s, int len) {
    int nw = _noWidth.allMatches(s).length;
    return s.padLeft(6 + nw);
  }

  ///
  /// How this is displayed in the LCD
  ///
  String get programDisplay;

  /// How this is displayed in a program listing
  String get programListing;

  /// (i)
  bool get argIsParenI => argValue == op.arg?.desc.indirectIndexNumber;

  /// I
  bool get argIsI => argValue == op.arg?.desc.indexRegisterNumber;

  @override
  String toString() => 'ProgramInstruction($programListing)';
}

///
/// A representation of all of the operations.  This is used by the model
/// to assign op codes and labels to [ProgramOperation]s.
///
class OperationMap<OT extends ProgramOperation> {
  final List<List<MKey<OT>?>> keys;
  final List<OT> numbers;
  final List<OT> special;

  /// Key entry shortcuts, like how on the 16C, I is RCL-I and (i) is RCL-(i)
  final Map<OT, ProgramInstruction> shortcuts;

  /// Maps from opCode to ProgramOperation.  Each operation occurs in the
  /// table 1+maxArg times.
  late final List<OT?> _operationTable;
  // (i) means "RCL (i)", and I means "RCL I".
  int _nextOpCode = 0;
  int _nextExtendedOpCode = 0;

  final List<OT> _inNumericOrder = List.empty(growable: true);
  // The extended (two-byte) opcodes, which are stored as 0xff followed by this
  final List<OT> _inNumericOrderExtended = List.empty(growable: true);

  final OT lbl; // The label instruction, for GTO and GSB implementation

  OperationMap._internal(
      this.keys, this.numbers, this.special, this.shortcuts, this.lbl);

  static OperationMap? _instance;

  factory OperationMap(
      {required List<List<MKey<OT>?>> keys,
      required List<OT> numbers,
      required List<OT> special,
      required Map<OT, ProgramInstruction> shortcuts,
      required OT lbl}) {
    final instance = _instance;
    if (instance == null) {
      final i = _instance =
          OperationMap<OT>._internal(keys, numbers, special, shortcuts, lbl);
      i._initializeProgramDisplay();
      i._initializeOperationTable();
      return i;
    } else {
      assert(instance.keys == keys);
      assert(instance.numbers == numbers);
      assert(instance.special == special);
      assert(instance.lbl == lbl);
      return instance as OperationMap<OT>;
    }
  }

  void _assignOpCode(OT o) {
    final int numOpCodes = o.numOpCodes;
    if (numOpCodes == o.numExtendedOpCodes) {
      o._opCode = -1;
    } else {
      o._opCode = _nextOpCode;
      _nextOpCode += numOpCodes;
      _inNumericOrder.add(o);
    }
    if (o.numExtendedOpCodes == 0) {
      o._extendedOpCode = -1;
    } else {
      o._extendedOpCode = _nextExtendedOpCode;
      _nextExtendedOpCode += o.numExtendedOpCodes;
      _inNumericOrderExtended.add(o);
    }
  }

  void _initializeOperationTable() {
    _operationTable = List.empty(growable: true);
    for (final OT o in _inNumericOrder) {
      assert(o.maxArg >= 0);
      for (int i = 0; i < o.numOpCodes; i++) {
        _operationTable.add(o);
      }
    }
    if (_inNumericOrderExtended.isEmpty) {
      assert(_operationTable.length < 0x100);
    } else {
      assert(_operationTable.length < 0xff);
      _operationTable.length = 0xff;
      for (final OT o in _inNumericOrderExtended) {
        assert(o.maxArg >= 0);
        for (int i = 0; i < o.numExtendedOpCodes; i++) {
          _operationTable.add(o);
        }
      }
      assert(_operationTable.length < 0x200);
    }
    _inNumericOrder.length = 0;
    _inNumericOrderExtended.length = 0;
  }

  void _initializeProgramDisplay() {
    assert(_inNumericOrder.isEmpty);
    final visited = <OT>{};
    for (int i = 0; i < special.length; i++) {
      final o = special[i];
      final ok = visited.add(o);
      assert(ok);
      o._programDisplay = '';
      o._opCode = ProgramOperation._invalidOpCodeStart - i;
    }
    for (final k in shortcuts.keys) {
      assert(!visited.contains(k));
      visited.add(k);
      // We will visit k, at the end, when the thing to which its
      // shortcut has been initialized.
    }
    for (int i = 0; i < numbers.length; i++) {
      final o = numbers[i];
      final ok = visited.add(o);
      assert(ok);
      o._programDisplay = ' ${i.toRadixString(16)}';
      _assignOpCode(o);
    }
    for (int row = 0; row < keys.length; row++) {
      final keyRow = keys[row];
      for (int col = 0; col < keyRow.length; col++) {
        final MKey<OT>? key = keyRow[col];
        if (key == null) {
          continue;
        }
        final String rcText;
        if (visited.contains(key.unshifted)) {
          if (key.unshifted._programDisplay != '') {
            // A number key
            assert(key.unshifted.maxArg == 0);
            rcText = key.unshifted._programDisplay;
          } else {
            rcText = '${row + 1}${(col + 1) % 10}';
          }
        } else {
          rcText = '${row + 1}${(col + 1) % 10}';
          visited.add(key.unshifted);
          if (key.unshifted.maxArg == 0) {
            key.unshifted._programDisplay = rcText;
          } else {
            key.unshifted._programDisplay = '$rcText ';
          }
          _assignOpCode(key.unshifted);
        }
        if (!visited.contains(key.fShifted)) {
          visited.add(key.fShifted);
          if (key.fShifted.maxArg == 0) {
            key.fShifted._programDisplay = '42 $rcText';
          } else {
            key.fShifted._programDisplay = '42,$rcText,';
          }
          _assignOpCode(key.fShifted);
        }
        if (!visited.contains(key.gShifted)) {
          visited.add(key.gShifted);
          if (key.gShifted.maxArg == 0) {
            key.gShifted._programDisplay = '43 $rcText';
          } else {
            key.gShifted._programDisplay = '43,$rcText,';
          }
          _assignOpCode(key.gShifted);
        }
        for (final MKeyExtensionOp<OT> ext in key.extensionOps) {
          ext.op._programDisplay = ext.programDisplayPrefix + rcText;
          _assignOpCode(ext.op);
        }
      }
    }
    shortcuts.forEach((ProgramOperation k, ProgramInstruction v) {
      assert(v.argValue >= 0 && v.argValue <= v.op.maxArg);
      k._opCode = v.op._opCode + v.argValue;
      k._programDisplay = v.op._programDisplay;
    });
  }
}

///
///  A listener that receives callbacks when a program delivers results
///  to the user.  This is used for testing.
///
class ProgramListener {
  /// Called when the program finishes normally, via a RTN instruction.
  void onDone() {}

  /// Called when an R/S instruction stops the program (usually in the
  /// middle, to deliver intermediate results).
  void onRS() {}

  /// Called when a PSE instruction momentarily pauses the program to
  /// display results.
  void onPause() {}

  /// Called when the program has a CalculatorError
  void onError(CalculatorError err) {}

  /// Called when the program is stopped due to a keypress
  void onStop() {}

  /// A future that completes when we should resume from a pause instruction,
  /// after [onPause()] is called.
  Future<void> resumeFromPause() => Future.delayed(const Duration(seconds: 1));
}
