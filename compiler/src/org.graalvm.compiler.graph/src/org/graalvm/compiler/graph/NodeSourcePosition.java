/*
 * Copyright (c) 2016, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */
package org.graalvm.compiler.graph;

import static org.graalvm.compiler.graph.NodeSourcePosition.Marker.None;
import static org.graalvm.compiler.graph.NodeSourcePosition.Marker.Placeholder;
import static org.graalvm.compiler.graph.NodeSourcePosition.Marker.Substitution;

import java.util.Objects;

import org.graalvm.compiler.bytecode.BytecodeDisassembler;
import org.graalvm.compiler.bytecode.Bytecodes;

import jdk.vm.ci.code.BytecodeFrame;
import jdk.vm.ci.code.BytecodePosition;
import jdk.vm.ci.code.CodeUtil;
import jdk.vm.ci.meta.JavaConstant;
import jdk.vm.ci.meta.JavaMethod;
import jdk.vm.ci.meta.MetaUtil;
import jdk.vm.ci.meta.ResolvedJavaMethod;

public class NodeSourcePosition extends BytecodePosition {

    /**
     * The receiver of the method this frame refers to.
     */
    private final JavaConstant receiver;
    private final int hashCode;
    private final Marker marker;

    /**
     * Remove marker frames.
     */
    public NodeSourcePosition trim() {
        if (marker != None) {
            return null;
        }
        NodeSourcePosition caller = getCaller();
        if (caller != null) {
            caller = caller.trim();
        }
        if (caller != getCaller()) {
            return new NodeSourcePosition(receiver, caller, getMethod(), getBCI());
        }
        return this;
    }

    enum Marker {
        None,
        Placeholder,
        Substitution
    }

    public NodeSourcePosition(JavaConstant receiver, NodeSourcePosition caller, ResolvedJavaMethod method, int bci) {
        this(receiver, caller, method, bci, None);
    }

    public NodeSourcePosition(JavaConstant receiver, NodeSourcePosition caller, ResolvedJavaMethod method, int bci, Marker marker) {
        super(caller, method, bci);
        if (caller == null) {
            this.hashCode = 31 * bci + method.hashCode();
        } else {
            this.hashCode = caller.hashCode * 7 + 31 * bci + method.hashCode();
        }
        this.receiver = receiver;
        this.marker = marker;
        assert receiver == null || marker != None || BytecodeFrame.isPlaceholderBci(bci) || method.getDeclaringClass().isInstance(receiver) : this;
    }

    public static NodeSourcePosition placeholder(ResolvedJavaMethod method) {
        return new NodeSourcePosition(null, null, method, BytecodeFrame.INVALID_FRAMESTATE_BCI, Placeholder);
    }

    public static NodeSourcePosition placeholder(ResolvedJavaMethod method, int bci) {
        return new NodeSourcePosition(null, null, method, bci, Placeholder);
    }

    public boolean isPlaceholder() {
        return marker == Placeholder;
    }

    public static NodeSourcePosition substitution(ResolvedJavaMethod method) {
        return new NodeSourcePosition(null, null, method, BytecodeFrame.INVALID_FRAMESTATE_BCI, Substitution);
    }

    public static NodeSourcePosition substitution(NodeSourcePosition caller, ResolvedJavaMethod method, int bci) {
        return new NodeSourcePosition(null, caller, method, bci, Substitution);
    }

    public boolean isSubstitution() {
        return marker == Substitution;
    }

    @Override
    public boolean equals(Object obj) {
        if (obj == this) {
            return true;
        }
        if (obj != null && getClass() == obj.getClass()) {
            NodeSourcePosition that = (NodeSourcePosition) obj;
            if (hashCode != that.hashCode) {
                return false;
            }
            if (this.getBCI() == that.getBCI() && Objects.equals(this.getMethod(), that.getMethod()) && Objects.equals(this.getCaller(), that.getCaller()) &&
                            Objects.equals(this.receiver, that.receiver)) {
                return true;
            }
        }
        return false;
    }

    @Override
    public int hashCode() {
        return hashCode;
    }

    public JavaConstant getReceiver() {
        return receiver;
    }

    public int depth() {
        int d = 0;
        NodeSourcePosition pos = this;
        while (pos != null) {
            d++;
            pos = pos.getCaller();
        }
        return d;
    }

    @Override
    public NodeSourcePosition getCaller() {
        return (NodeSourcePosition) super.getCaller();
    }

    public NodeSourcePosition addCaller(JavaConstant newCallerReceiver, NodeSourcePosition link, boolean isSubstitution) {
        if (getCaller() == null) {
            if (isPlaceholder()) {
                return new NodeSourcePosition(newCallerReceiver, link, getMethod(), 0);
            }
            assert newCallerReceiver == null || receiver == null : "replacing receiver";
            assert link == null || isSubstitution || verifyCaller(this, link) : link;

            return new NodeSourcePosition(newCallerReceiver, link, getMethod(), getBCI());
        } else {
            return new NodeSourcePosition(receiver, getCaller().addCaller(newCallerReceiver, link, isSubstitution), getMethod(), getBCI());
        }
    }

    public NodeSourcePosition addCaller(JavaConstant newCallerReceiver, NodeSourcePosition link) {
        return addCaller(newCallerReceiver, link, false);
    }

    public NodeSourcePosition addCaller(NodeSourcePosition link) {
        return addCaller(null, link);
    }

    @Override
    public String toString() {
        StringBuilder sb = new StringBuilder(100);
        NodeSourcePosition pos = this;
        while (pos != null) {
            format(sb, pos);
            pos = pos.getCaller();
            if (pos != null) {
                sb.append(CodeUtil.NEW_LINE);
            }
        }
        return sb.toString();
    }

    private static void format(StringBuilder sb, NodeSourcePosition pos) {
        MetaUtil.appendLocation(sb.append("at "), pos.getMethod(), pos.getBCI());
        if (pos.receiver != null) {
            sb.append(" receiver=" + pos.receiver);
        }
        String disassembly = BytecodeDisassembler.disassembleOne(pos.getMethod(), pos.getBCI());
        if (disassembly != null && disassembly.length() > 0) {
            sb.append(" // ");
            sb.append(disassembly);
        }
    }

    String shallowToString() {
        StringBuilder sb = new StringBuilder(100);
        format(sb, this);
        return sb.toString();
    }

    public boolean verify() {
        NodeSourcePosition current = this;
        NodeSourcePosition caller = getCaller();
        while (caller != null) {
            assert verifyCaller(current, caller) : current;
            current = caller;
            caller = caller.getCaller();
        }
        return true;
    }

    private static boolean verifyCaller(NodeSourcePosition current, NodeSourcePosition caller) {
        if (BytecodeFrame.isPlaceholderBci(caller.getBCI())) {
            return true;
        }
        int opcode = BytecodeDisassembler.getBytecodeAt(caller.getMethod(), caller.getBCI());
        JavaMethod method = BytecodeDisassembler.getInvokedMethodAt(caller.getMethod(), caller.getBCI());
        /*
         * It's not really possible to match the declaring classes since this might be an interface
         * invoke. Matching name and signature probably provides enough accuracy.
         */
        assert method == null || (method.getName().equals(current.getMethod().getName()) &&
                        method.getSignature().equals(current.getMethod().getSignature())) ||
                        caller.getMethod().getName().equals("linkToTargetMethod") ||
                        opcode == Bytecodes.INVOKEDYNAMIC ||
                        caller.getMethod().getDeclaringClass().getName().startsWith("Ljava/lang/invoke/LambdaForm$") ||
                        current.getMethod().getName().equals("callInlined") : "expected " + method + " but found " +
                                        current.getMethod();
        return true;
    }
}
