/*
MIT License

Copyright (c) 2021 William Foote

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

import 'dart:async';

import 'package:jrpn/c/operations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jrpn/c/controller.dart';
import 'package:jrpn/m/model.dart';

import 'package:jrpn/main.dart';
import 'programs.dart';

Future<void> main() async {
  testWidgets('Self tests', (WidgetTester tester) async {
    await tester.pumpWidget(Jrpn(Controller(Model())));
  });

  test('p79 program', p79_program);
  test('p93 checksum program', p93_checksum);
  test('stack lift', test_stack_lift);
  test('registers and word size', test_registers_and_word_size);
  test('program with error', program_with_error);
  test('last x', last_x);
  test('no scroll reset', no_scroll_reset);
  appendixA();
  test('Towers of Hanoi', towers_of_hanoi);
  // Do this last, because it leaves a timer pending:
  test('Built-in self tests', () async {
    await SelfTests(inCalculator: false).runAll();
  });


}

void enter(Controller c, Operation key) {
  c.buttonDown(key);
  c.buttonUp();
}

Future<void> no_scroll_reset() async {
  // p. 100
  final ops = [
    Operations.minus,
    Operations.plus,
    Operations.mult,
    Operations.div,
    Operations.rmd,
    Operations.dblx,
    Operations.dblDiv,
    Operations.dblr,
    Operations.xor,
    Operations.not,
    Operations.or,
    Operations.and,
    Operations.abs,
    Operations.sqrtOp,
    Operations.wSize,
    Operations.lj,
    Operations.asr,
    Operations.rl,
    Operations.rr,
    Operations.rlcn,
    Operations.rrcn,
    Operations.maskl,
    Operations.maskr,
    Operations.sb,
    Operations.cb,
    Operations.bQuestion,
    Operations.rlcn,
    Operations.rrn,
    Operations.poundB,
    Operations.chs
  ];
  final fops = [
    Operations.minus,
    Operations.plus,
    Operations.mult,
    Operations.div,
    Operations.reciprocal,
    Operations.abs,
    Operations.sqrtOp,
  ];
  final Value four = Value.fromInternal(BigInt.parse('4'));
  for (final Operation op in ops) {
    final m = Model<Operation>();
    final c = Controller(m);

    enter(c, Operations.n3);
    enter(c, Operations.enter);
    enter(c, Operations.n2);
    enter(c, Operations.enter);
    enter(c, Operations.n1);
    enter(c, Operations.enter);
    enter(c, Operations.n4);
    expect(m.lastX, Value.zero);
    enter(c, op);
    expect(m.lastX, four, reason: 'lastx for ${op.name}');
  }
  for (final Operation op in fops) {
    final m = Model<Operation>();
    final c = Controller(m);

    enter(c, Operations.floatKey);
    enter(c, Operations.n2);
    enter(c, Operations.n3);
    enter(c, Operations.enter);
    enter(c, Operations.n2);
    enter(c, Operations.enter);
    enter(c, Operations.n1);
    enter(c, Operations.enter);
    enter(c, Operations.n4);
    expect(m.lastX, Value.zero);
    enter(c, op);
    expect(m.lastX.asDouble, 4.0, reason: 'lastx for float mode ${op.name}');
  }
}

Future<void> last_x() async {
  // p. 100
  final ops = [
    Operations.minus,
    Operations.plus,
    Operations.mult,
    Operations.div,
    Operations.rmd,
    Operations.dblx,
    Operations.dblDiv,
    Operations.dblr,
    Operations.xor,
    Operations.not,
    Operations.or,
    Operations.and,
    Operations.abs,
    Operations.sqrtOp,
    Operations.wSize,
    Operations.lj,
    Operations.asr,
    Operations.rl,
    Operations.rr,
    Operations.rlcn,
    Operations.rrcn,
    Operations.maskl,
    Operations.maskr,
    Operations.sb,
    Operations.cb,
    Operations.bQuestion,
    Operations.rlcn,
    Operations.rrn,
    Operations.poundB,
    Operations.chs
  ];
  final fops = [
    Operations.minus,
    Operations.plus,
    Operations.mult,
    Operations.div,
    Operations.reciprocal,
    Operations.abs,
    Operations.sqrtOp,
  ];
  final Value four = Value.fromInternal(BigInt.parse('4'));
  for (final program in [ false, true ]) {
    for (final Operation op in ops) {
      final tc = TestCalculator();
      final c = tc.controller;
      final m = tc.model;
      if (program) {
        enter(c, Operations.pr);
      }
      enter(c, Operations.n3);
      enter(c, Operations.enter);
      enter(c, Operations.n2);
      enter(c, Operations.enter);
      enter(c, Operations.n1);
      enter(c, Operations.enter);
      enter(c, Operations.n4);
      expect(m.lastX, Value.zero);
      enter(c, op);
      if (program) {
        final out = StreamIterator<ProgramEvent>(tc.output.stream);
        enter(c, Operations.rtn);  // An extra one in case of branching instr.
        enter(c, Operations.pr);
        enter(c, Operations.rs);
        expect(await out.moveNext(), true);
        expect(out.current, ProgramEvent.done);
      }
      expect(m.lastX, four, reason: 'lastx for ${op.name}');
    }
    for (final Operation op in fops) {
      final tc = TestCalculator();
      final m = tc.model;
      final c = tc.controller;
      if (program) {
        enter(c, Operations.pr);
      }

      enter(c, Operations.floatKey);
      enter(c, Operations.n2);
      enter(c, Operations.n3);
      enter(c, Operations.enter);
      enter(c, Operations.n2);
      enter(c, Operations.enter);
      enter(c, Operations.n1);
      enter(c, Operations.enter);
      enter(c, Operations.n4);
      if (!program) {
        expect(m.lastX, Value.zero);
      }
      if (program) {
        final out = StreamIterator<ProgramEvent>(tc.output.stream);
        enter(c, Operations.rtn);  // An extra one in case of branching instr.
        enter(c, Operations.pr);
        enter(c, Operations.rs);
        expect(await out.moveNext(), true);
        expect(out.current, ProgramEvent.done);
      }
      enter(c, op);
      expect(m.lastX.asDouble, 4.0, reason: 'lastx for float mode ${op.name}');
    }
  }
}

Future<void> program_with_error() async {
  final tc = TestCalculator();
  final m = tc.model;
  final c = tc.controller;
  var out = StreamIterator<ProgramEvent>(tc.output.stream);

  enter(c, Operations.pr);
  enter(c, Operations.lbl);
  enter(c, Operations.a);
  enter(c, Operations.floatKey);
  enter(c, Operations.n2);
  enter(c, Operations.n0);
  enter(c, Operations.reciprocal);
  enter(c, Operations.pr);
  enter(c, Operations.gsb);
  enter(c, Operations.a);
  await out.moveNext();
  expect(out.current.errorNumber, 0);
  expect(m.display.current, '   error 0  ');

  enter(c, Operations.clearPrefix); // Clear error display
  enter(c, Operations.pr); // Program mode
  enter(c, Operations.clearPrgm);
  enter(c, Operations.lbl);
  enter(c, Operations.a);
  enter(c, Operations.n1);
  enter(c, Operations.plus);
  enter(c, Operations.gsb);
  enter(c, Operations.a);
  enter(c, Operations.pr);
  enter(c, Operations.n0);
  enter(c, Operations.enter);
  enter(c, Operations.enter);
  enter(c, Operations.enter);
  enter(c, Operations.gsb);
  enter(c, Operations.a);
  expect(await out.moveNext(), true);
  expect(out.current.errorNumber, 5);
  expect(m.display.current, '   error 5  ');
  enter(c, Operations.a);
  expect(m.display.current.trim(), '5.00');
}

Future<void> test_registers_and_word_size() async {
  // p. 67:
  final m = Model<Operation>();
  final c = Controller(m);

  enter(c, Operations.hex);
  enter(c, Operations.n1);
  enter(c, Operations.n0);
  enter(c, Operations.wSize);
  enter(c, Operations.clearReg);
  enter(c, Operations.n1);
  enter(c, Operations.n2);
  enter(c, Operations.n3);
  enter(c, Operations.n4);
  enter(c, Operations.sto);
  enter(c, Operations.n0);
  enter(c, Operations.n5);
  enter(c, Operations.n6);
  enter(c, Operations.n7);
  enter(c, Operations.n8);
  enter(c, Operations.sto);
  enter(c, Operations.n1);
  enter(c, Operations.n2);
  enter(c, Operations.n0);
  enter(c, Operations.wSize);
  enter(c, Operations.rcl);
  enter(c, Operations.n0);
  expect(m.xI, BigInt.parse('56781234', radix: 16));
  enter(c, Operations.rcl);
  enter(c, Operations.n1);
  expect(m.xI, BigInt.parse('0', radix: 16));
  enter(c, Operations.n1);
  enter(c, Operations.n0);
  enter(c, Operations.wSize);
  enter(c, Operations.rcl);
  enter(c, Operations.n0);
  expect(m.xI, BigInt.parse('1234', radix: 16));
  enter(c, Operations.rcl);
  enter(c, Operations.n1);
  expect(m.xI, BigInt.parse('5678', radix: 16));

  // p. 70:
  enter(c, Operations.n0);
  enter(c, Operations.enter);
  enter(c, Operations.enter);
  enter(c, Operations.enter);
  enter(c, Operations.dec);
  enter(c, Operations.n0);
  enter(c, Operations.wSize);
  enter(c, Operations.n3);
  enter(c, Operations.n2);
  enter(c, Operations.n6);
  enter(c, Operations.sto);
  enter(c, Operations.I);
  enter(c, Operations.n4);
  enter(c, Operations.wSize);
  enter(c, Operations.n3);
  enter(c, Operations.sto);
  enter(c, Operations.parenI);
  enter(c, Operations.bsp);
  enter(c, Operations.rcl);
  enter(c, Operations.parenI);
  expect(m.xI, BigInt.parse('3'));
  expect(m.yI, BigInt.parse('6')); // 326 & 15
  expect(m.z, Value.zero); // 326 & 15
}

Future<void> test_stack_lift() async {
  for (final program in [ false, true ]) {
    final tc = TestCalculator();
    final m = tc.model;
    final c = tc.controller;

    // p. 67:
    m.displayMode = DisplayMode.float(2);
    if (program) {
      enter(c, Operations.pr);
    }
    enter(c, Operations.n4);
    enter(c, Operations.n2);
    enter(c, Operations.floatKey);
    enter(c, Operations.n0);
    enter(c, Operations.eex);
    enter(c, Operations.n8);
    enter(c, Operations.sto);
    enter(c, Operations.n0);
    if (program) {
      enter(c, Operations.clx);
    } else {
      enter(c, Operations.bsp);
    }
    enter(c, Operations.rcl);
    enter(c, Operations.n0);
    enter(c, Operations.n2);
    enter(c, Operations.mult);
    if (program) {
      final out = StreamIterator<ProgramEvent>(tc.output.stream);
      enter(c, Operations.pr);
      enter(c, Operations.rs);
      expect(await out.moveNext(), true);
      expect(out.current, ProgramEvent.done);
    }
    expect(m.xF, 200000000.0);
    expect(m.yF, 42.0);
    expect(m.z, Value.zero);
  }
}
