; RUN: llc -mtriple=x86_64-windows-msvc < %s | FileCheck %s --check-prefix=X64
; RUN: llc -mtriple=i686-windows-msvc < %s | FileCheck %s --check-prefix=X86

declare ptr @llvm.frameaddress(i32)
declare void @llvm.localescape(...)
declare ptr @llvm.localaddress()
declare ptr @llvm.localrecover(ptr, ptr, i32)
declare i32 @printf(ptr, ...)

@str = internal constant [10 x i8] c"asdf: %d\0A\00"

define void @print_framealloc_from_fp(ptr %fp) {
  %a.i8 = call ptr @llvm.localrecover(ptr @alloc_func, ptr %fp, i32 0)
  %a.val = load i32, ptr %a.i8
  call i32 (ptr, ...) @printf(ptr @str, i32 %a.val)
  %b.i8 = call ptr @llvm.localrecover(ptr @alloc_func, ptr %fp, i32 1)
  %b.val = load i32, ptr %b.i8
  call i32 (ptr, ...) @printf(ptr @str, i32 %b.val)
  store i32 42, ptr %b.i8
  %b2 = getelementptr i32, ptr %b.i8, i32 1
  %b2.val = load i32, ptr %b2
  call i32 (ptr, ...) @printf(ptr @str, i32 %b2.val)
  ret void
}

; X64-LABEL: print_framealloc_from_fp:
; X64: movq %rcx, %[[parent_fp:[a-z]+]]
; X64: movl .Lalloc_func$frame_escape_0(%rcx), %edx
; X64: leaq {{.*}}(%rip), %[[str:[a-z]+]]
; X64: movq %[[str]], %rcx
; X64: callq printf
; X64: movl .Lalloc_func$frame_escape_1(%[[parent_fp]]), %edx
; X64: movq %[[str]], %rcx
; X64: callq printf
; X64: movl    $42, .Lalloc_func$frame_escape_1(%[[parent_fp]])
; X64: retq

; X86-LABEL: print_framealloc_from_fp:
; X86: pushl   %esi
; X86: movl    8(%esp), %esi
; X86: pushl   Lalloc_func$frame_escape_0(%esi)
; X86: pushl   $_str
; X86: calll   _printf
; X86: addl    $8, %esp
; X86: pushl   Lalloc_func$frame_escape_1(%esi)
; X86: pushl   $_str
; X86: calll   _printf
; X86: addl    $8, %esp
; X86: movl    $42, Lalloc_func$frame_escape_1(%esi)
; X86: movl    $4, %eax
; X86: pushl   Lalloc_func$frame_escape_1(%esi,%eax)
; X86: pushl   $_str
; X86: calll   _printf
; X86: addl    $8, %esp
; X86: popl    %esi
; X86: retl

define void @alloc_func(i32 %n) {
  %a = alloca i32
  %b = alloca i32, i32 2
  call void (...) @llvm.localescape(ptr %a, ptr %b)
  store i32 42, ptr %a
  store i32 13, ptr %b

  ; Force usage of EBP with a dynamic alloca.
  alloca i8, i32 %n

  %lp = call ptr @llvm.localaddress()
  call void @print_framealloc_from_fp(ptr %lp)
  ret void
}

; X64-LABEL: alloc_func:
; X64: pushq   %rbp
; X64: subq    $16, %rsp
; X64: .seh_stackalloc 16
; X64: leaq    16(%rsp), %rbp
; X64: .seh_setframe %rbp, 16
; X64: .Lalloc_func$frame_escape_0 = -4
; X64: .Lalloc_func$frame_escape_1 = -12
; X64: movl $42, -4(%rbp)
; X64: movl $13, -12(%rbp)
; X64: movq 	%rbp, %rcx
; X64: callq print_framealloc_from_fp
; X64: retq

; X86-LABEL: alloc_func:
; X86: pushl   %ebp
; X86: movl    %esp, %ebp
; X86: subl    $12, %esp
; X86: Lalloc_func$frame_escape_0 = -4
; X86: Lalloc_func$frame_escape_1 = -12
; X86: movl    $42, -4(%ebp)
; X86: movl    $13, -12(%ebp)
; X86: pushl   %ebp
; X86: calll   _print_framealloc_from_fp
; X86: movl    %ebp, %esp
; X86: popl    %ebp
; X86: retl

; Helper to make this a complete program so it can be compiled and tested.
define i32 @main() {
  call void @alloc_func(i32 3)
  ret i32 0
}

define void @alloc_func_no_frameaddr() {
  %a = alloca i32
  %b = alloca i32
  call void (...) @llvm.localescape(ptr %a, ptr %b)
  store i32 42, ptr %a
  store i32 13, ptr %b
  call void @print_framealloc_from_fp(ptr null)
  ret void
}

; X64-LABEL: alloc_func_no_frameaddr:
; X64: subq    $40, %rsp
; X64: .seh_stackalloc 40
; X64: .seh_endprologue
; X64: .Lalloc_func_no_frameaddr$frame_escape_0 = 36
; X64: .Lalloc_func_no_frameaddr$frame_escape_1 = 32
; X64: movl $42, 36(%rsp)
; X64: movl $13, 32(%rsp)
; X64: xorl %ecx, %ecx
; X64: callq print_framealloc_from_fp
; X64: .seh_startepilogue
; X64: addq $40, %rsp
; X64: .seh_endepilogue
; X64: retq

; X86-LABEL: alloc_func_no_frameaddr:
; X86: subl    $8, %esp
; X86: Lalloc_func_no_frameaddr$frame_escape_0 = 4
; X86: Lalloc_func_no_frameaddr$frame_escape_1 = 0
; X86: movl $42, 4(%esp)
; X86: movl $13, (%esp)
; X86: pushl $0
; X86: calll _print_framealloc_from_fp
; X86: addl    $12, %esp
; X86: retl
