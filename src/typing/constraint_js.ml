(**
 * Copyright (c) 2014, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the "flow" directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 *
 *)

(* This module defines the ML data types that represent types in Flow. *)

open Utils
open Utils_js
open Modes_js
open Reason_js

module Ast = Spider_monkey_ast

(******************************************************************************)
(* Types                                                                      *)
(******************************************************************************)

(* Some types represent definitions. These include numbers, strings, booleans,
   functions, classes, objects, arrays, and such. The shape of these types
   should be fairly obvious.
   Other types represent uses. These include function applications, class
   instantiations, property accesses, element accesses, operations such as
   addition, predicate refinements, etc. The shape of these types is somewhat
   trickier, but do follow a pattern. Typically, such a type consists of the
   arguments to the operation, and a type variable capturing the result of the
   operation. A full understanding of the semantics of such types requires a
   look at the subtyping relation, described in the module Flow_js. *)

(* Every type has (or should have, if not already) a "reason" for its
   existence. This information is captured in the type itself for now, but
   should be separated out in the future.
   Types that represent definitions point to the positions of such
   definitions (or values). Types that represent uses point to the positions of
   such uses (or operations). These reasons are logged, chained, etc. by the
   implementation of the subtyping algorithm, that effectively constructs a
   proof of the typing derivation based on these reasons as axioms. *)

type ident = int
type name = string

module Type = struct
  type t =
  (* open type variable *)
  (* A type variable (tvar) is an OpenT(reason, id) where id is an int index
     into a context's graph: a context's graph is a map from tvar ids to nodes
     (see below). *)
  (** Note: ids are globally unique. tvars are "owned" by a single context, but
      that context and its tvars may later be merged into other contexts. **)
  | OpenT of reason * ident

  (*************)
  (* def types *)
  (*************)

  (* TODO: constant types *)

  | NumT of reason * number_literal literal
  | StrT of reason * string literal
  | BoolT of reason * bool option
  | UndefT of reason
  | MixedT of reason
  | AnyT of reason
  | NullT of reason
  | VoidT of reason

  | FunT of reason * static * prototype * funtype
  | ObjT of reason * objtype
  | ArrT of reason * t * t list

  (* type of a class *)
  | ClassT of t
  (* type of an instance of a class *)
  | InstanceT of reason * static * super * insttype

  (* type of an optional parameter *)
  | OptionalT of t
  (* type of a rest parameter *)
  | RestT of t

  (** A polymorphic type is like a type-level "function" that, when applied to
      lists of type arguments, generates types. Just like a function, a
      polymorphic type has a list of type parameters, represented as bound type
      variables. We say that type parameters are "universally quantified" (or
      "universal"): every substitution of type arguments for type parameters
      generates a type. Dually, we have "existentially quantified" (or
      "existential") type variables: such a type variable denotes some, possibly
      unknown, type. Universal type parameters may specify subtype constraints
      ("bounds"), which must be satisfied by any types they may be substituted
      by. Evaluation of existential types, which involves generating fresh type
      variables, never happens under polymorphic types; it is forced only when
      polymorphic types are applied. **)

  (* polymorphic type *)
  | PolyT of typeparam list * t
  (* type application *)
  | TypeAppT of t * t list
  (* bound type variable *)
  | BoundT of typeparam
  (* existential type variable *)
  | ExistsT of reason

  (* ? types *)
  | MaybeT of t

  (* & types *)
  | IntersectionT of reason * t list

  (* | types *)
  | UnionT of reason * t list

  (* generalizations of AnyT *)
  | UpperBoundT of t (* any upper bound of t *)
  | LowerBoundT of t (* any lower bound of t *)

  (* specializations of AnyT *)
  | AnyObjT of reason (* any object *)
  | AnyFunT of reason (* any function *)

  (* constrains some properties of an object *)
  | ShapeT of t
  | DiffT of t * t

  (* collects the keys of an object *)
  | KeysT of reason * t
  (* singleton string, matches exactly a given string literal *)
  | SingletonStrT of reason * string
  (* matches exactly a given number literal, for some definition of "exactly"
     when it comes to floats... *)
  | SingletonNumT of reason * number_literal
  (* singleton bool, matches exactly a given boolean literal *)
  | SingletonBoolT of reason * bool

  (* type aliases *)
  | TypeT of reason * t

  (* annotations *)
  (**
      A type that annotates a storage location performs two functions:
      * it constrains the types of values stored into the location
      * it masks the actual type of values retrieved from the location,
      giving instead a pro forma type which all such values are
      considered as having.

      In the former role, the annotated type behaves as an upper bound
      interacting with inflowing lower bounds - these interactions may
      occur e.g. as a result of values being stored to type-annotated
      variables, or arguments flowing to type-annotated parameters.

      In the latter role, the annotated type behaves as a lower bound,
      flowing to sites where values stored in the annotated location are
      used (such as users of a variable, or users of a parameter within
      a function body).

      When a type annotation resolves immediately to a concrete type
      (say, number = NumT or string = StrT), this single type would
      suffice to perform both roles. However, when an annotation has
      not yet been resolved, we can't simply use a type variable as a
      placeholder as we can elsewhere.

      TL;DR type variables are conductors; annotated types are insulators. :)

      For an annotated type, we must collect incoming lower bounds and
      downstream upper bounds without allowing them to interact with each
      other. If we did, the annotation would be "translucent", leaking
      type information about incoming values - failing to perform the
      second of the two roles noted above.

      Using a single type variable would allow exactly this propagation:
      it's essentially what type variables do.

      To accomplish the desired insulation we represent an annotation with
      a pair of type variables: a "sink" that collects lower bounds flowing
      into the annotation, and a "source" that collects downstream uses of
      the annotated location as upper bounds.

      The source tvar is linked to the unresolved definition's tvar.
      When that definition is resolved, the concrete type will flow
      into the annotation's source tvar as a lower bound.
      At that point two things will happen:

      * the source tvar will (as usual) evaluate the concrete definition
      against its accumulated upper bounds - this checks downstream use
      sites for compatibility with the annotated type.

      * a UnifyT edge, put in place at the time the AnnotT was built,
      will trigger a unification of the source and sink tvars. Critically,
      this will cause the concrete definition type to appear in the sink
      as an upper bound, prompting the check of all inflowing lower bounds
      against it.

      Of course, inflowing lower bounds and downstream upper bounds may
      continue to accumulate following this unification. As they do,
      they'll be checked against their respective sides of the bonded pair
      as usual.
  **)
  | AnnotT of t * t

  (* failure case for speculative matching *)
  | SpeculativeMatchFailureT of reason * t * t

  (* Stores exports (and potentially other metadata) for a module *)
  | ModuleT of reason * exporttypes

  (*************)
  (* use types *)
  (*************)

  (* operation on literals *)
  | SummarizeT of reason * t

  (* operations on runtime values, such as functions, objects, and arrays *)
  | CallT of reason * funtype
  | MethodT of reason * name * funtype
  | SetPropT of reason * proptype * t
  | GetPropT of reason * proptype * t
  | SetElemT of reason * t * t
  | GetElemT of reason * t * t

  (* operations on runtime types, such as classes and functions *)
  | ConstructorT of reason * t list * t
  | SuperT of reason * insttype
  | ExtendsT of t list * t * t

  (* overloaded +, could be subsumed by general overloading *)
  | AdderT of reason * t * t
  (* overloaded relational operator, could be subsumed by general overloading *)
  | ComparatorT of reason * t

  (* operation specifying a type refinement via a predicate *)
  | PredicateT of predicate * t

  (* == *)
  | EqT of reason * t

  (* logical operators *)
  | AndT of reason * t * t
  | OrT of reason * t * t
  | NotT of reason * t

  (* operation on polymorphic types *)
  (** SpecializeT(_, cache, targs, tresult) instantiates a polymorphic type with
      type arguments targs, and flows the result into tresult. If cache is set,
      it looks up a cache of existing instantiations for the type parameters of
      the polymorphic type, unifying the type arguments with those
      instantiations if such exist. **)
  | SpecializeT of reason * bool * t list * t

  (* operation on prototypes *)
  (** LookupT(_, strict, try_ts_on_failure, x, tresult) looks for property x in
      an object type, unifying its type with tresult. When x is not found, we
      have the following cases:

      (1) try_ts_on_failure is not empty, and we try to look for property x in
      the next object type in that list;

      (2) strict = None, so no error is reported;

      (3) strict = Some reason, so the position in reason is blamed.
  **)
  | LookupT of reason * reason option * t list * string * t

  (* operations on objects *)
  | ObjAssignT of reason * t * t * string list * bool
  | ObjFreezeT of reason * t
  | ObjRestT of reason * string list * t
  | ObjSealT of reason * t
  (** test that something is object-like, returning a default type otherwise **)
  | ObjTestT of reason * t * t

  (* Guarded unification (bidirectional).
     Remodel as unidirectional GuardT(l,u)? *)
  | UnifyT of t * t

  (* unifies with incoming concrete lower bound *)
  | BecomeT of reason * t

  (* manage a worklist of types to be concretized *)
  | ConcretizeT of t * t list * t list * t
  (* sufficiently concrete type *)
  | ConcreteT of t

  (* Keys *)
  | GetKeysT of reason * t
  | HasKeyT of reason * string

  (* Element access *)
  | ElemT of reason * t * t

  (* Module import handling *)
  | CJSRequireT of reason * t
  | ImportModuleNsT of reason * t
  | ImportTypeT of reason * t
  | ImportTypeofT of reason * t

  (* Module export handling *)
  | CJSExtractNamedExportsT of
      reason
      * (* local ModuleT *) t
      * (* 't_out' to receive the resolved ModuleT *) t_out
  | SetCJSExportT of reason * t * t_out
  | SetNamedExportsT of reason * t SMap.t * t_out

  and predicate =
  | AndP of predicate * predicate
  | OrP of predicate * predicate
  | NotP of predicate

  (* mechanism to handle binary tests where both sides need to be evaluated *)
  | LeftP of binary_test * t
  | RightP of binary_test * t

  (* truthy *)
  | ExistsP

  (* typeof, null check, Array.isArray *)
  | IsP of string

  and binary_test =
  (* e1 instanceof e2 *)
  | Instanceof
  (* e1.key === e2 *)
  | SentinelProp of string

  and 'a literal =
    | Literal of 'a
    | Truthy
    | Falsy
    | AnyLiteral

  and number_literal = (float * string)

  (* used by FunT and CallT *)
  and funtype = {
    this_t: t;
    params_tlist: t list;
    params_names: string list option;
    return_t: t;
    closure_t: int
  }

  and objtype = {
    flags: flags;
    dict_t: dicttype option;
    props_tmap: int;
    proto_t: prototype;
  }

  and proptype = reason * name

  and sealtype =
    | UnsealedInFile of string option
    | Sealed

  and flags = {
    frozen: bool;
    sealed: sealtype;
    exact: bool;
  }

  and dicttype = {
    dict_name: string option;
    key: t;
    value: t;
  }

  and polarity =
    | Negative      (* contravariant *)
    | Neutral       (* invariant *)
    | Positive      (* covariant *)

  and insttype = {
    class_id: ident;
    type_args: t SMap.t;
    arg_polarities: polarity SMap.t;
    fields_tmap: int;
    methods_tmap: int;
    mixins: bool;
    structural: bool;
  }

  and exporttypes = {
    (**
     * tmap used to store individual, named ES exports as generated by `export`
     * statements in a module. Note that this includes `export type` as well.
     *
     * Note that CommonJS modules may also populate this tmap if their export
     * type is an object (that object's properties become named exports) or if
     * it has any "type" exports via `export type ...`.
     *)
    exports_tmap: int;

    (**
     * This stores the CommonJS export type when applicable and is used as the
     * exact return type for calls to require(). This slot doesn't apply to pure
     * ES modules.
     *)
    cjs_export: t option;
  }

  and typeparam = {
    reason: reason;
    name: string;
    bound: t;
    polarity: polarity
  }

  and prototype = t

  and super = t

  and static = t

  and properties = t SMap.t

  and t_out = t

  let compare = Pervasives.compare

  let open_tvar tvar =
    match tvar with
    | OpenT(reason,id) -> (reason,id)
    | _ -> assert false

end

(* The typechecking algorithm often needs to maintain sets of types, or more
   generally, maps of types (for logging we need to associate some provenanced
   information to types). *)

module TypeSet : Set.S with type elt = Type.t
  = Set.Make(Type)

module TypeMap : MapSig with type key = Type.t
  = MyMap(Type)

(*****************************************************************)

(*
  Terminology:

   * A step records a single test of lower bound against
   upper bound, analogous to an invocation of the flow function.

   * A step may have a tvar as its lower or upper bound (or both).
   tvars act as conduits for concrete types, so steps which
   begin or end in tvars may be joined with other steps
   representing tests which adjoin the same tvar.

   The resulting sequence of steps, corresponding to an invocation
   of the flow function followed by the extension of the original
   lower/upper pair through any adjacent type variables, forms the
   basis of a trace. (In trace dumps this is called a "path".)

   * When a step has been induced recursively from a prior invocation
   of the flow function, it's said to have the trace associated with
   that invocation as a parent.

   (Note that each step in a path may have its own parent: consider
   an incoming, recursively induced step joining with a dormant step
   attached to some tvar in an arbitrarily removed invocation of the
   flow function.)

   * A trace is just a sequence of steps along with a (possibly empty)
   parent trace for each step. Since steps may share parents,
   a trace forms a graph, though it is naturally built up as a tree
   when recorded during evaluation of the flow function.
   (The formatting we do in reasons_of_trace recovers the graph
   structure for readability.)
 *)
module Trace = struct
  type step = Type.t * Type.t * parent * int
  and t = step list
  and parent = Parent of t

  let compare = Pervasives.compare

  (* trace depth is 1 + the length of the longest ancestor chain
     in the trace. We keep this precomputed because a) actual ancestors
     may be thrown away due to externally imposed limits on trace depth;
     b) the recursion limiter in the flow function checks this on every
     call. *)
  let trace_depth trace =
    List.fold_left (fun acc (_, _, _, d) -> max acc d) 0 trace

  (* Single-step trace with no parent. This corresponds to a
     top-level invocation of the flow function, e.g. due to
     a constraint generated in Type_inference_js *)
  let unit_trace lower upper =
    [lower, upper, Parent [], 1]

  (* Single-step trace with a parent. This corresponds to a
     recursive invocation of the flow function.
     Optimization: only embed when modes.trace > 0,
     because otherwise we're not going to see any traces anyway.
  *)
  let rec_trace lower upper parent =
    let parent_depth = trace_depth parent in
    let parent = if modes.traces > 0 then parent else [] in
    [lower, upper, Parent parent, parent_depth + 1]

  (* join two traces (see comment header *)
  let join_trace = (@)

  (* join a list of traces *)
  let concat_trace = List.concat

end

(* for export *)
type trace = Trace.t

let trace_depth = Trace.trace_depth
let unit_trace = Trace.unit_trace
let rec_trace = Trace.rec_trace
let join_trace = Trace.join_trace
let concat_trace = Trace.concat_trace

(* used to index trace nodes *)
module TraceMap : MapSig with type key = Trace.t
  = MyMap(Trace)

(* index the nodes in a trace down to a given level.
   returns two maps, trace -> index and index -> trace
 *)
let index_trace = Trace.(
  let rec f (level, tmap, imap) trace =
    if level <= 0 || TraceMap.mem trace tmap
    then level, tmap, imap
    else (
      let tmap, imap =
        let i = TraceMap.cardinal tmap in
        TraceMap.(add trace i tmap), IMap.(add i trace imap)
      in
      List.fold_left (fun acc (_, _, Parent parent, _) ->
        match parent with [] -> acc | _ -> f acc parent
      ) (level - 1, tmap, imap) trace
    )
  in
  fun level trace ->
    let _, tmap, imap = f (level, TraceMap.empty, IMap.empty) trace in
    tmap, imap
)


(*****************************************************************)

open Type

(* type constants *)

module type PrimitiveType = sig
  val desc: string
  val make: reason -> Type.t
end

module type PrimitiveT = sig
  val desc: string
  val t: Type.t
  val at: Loc.t -> Type.t
  val why: reason -> Type.t
  val tag: string -> Type.t
end

module Primitive (P: PrimitiveType) = struct
  let desc = P.desc
  let t = P.make (reason_of_string desc)
  let at tok = P.make (mk_reason desc tok)
  let why reason = P.make (replace_reason desc reason)
  let tag s = P.make (reason_of_string (desc ^ " (" ^ s ^ ")"))
end

module NumT = Primitive (struct
  let desc = "number"
  let make r = NumT (r, AnyLiteral)
end)

module StrT = Primitive (struct
  let desc = "string"
  let make r = StrT (r, AnyLiteral)
end)

module BoolT = Primitive (struct
  let desc = "boolean"
  let make r = BoolT (r, None)
end)

module MixedT = Primitive (struct
  let desc = "mixed"
  let make r = MixedT r
end)

module UndefT = Primitive (struct
  let desc = ""
  let make r = UndefT r
end)

module AnyT = Primitive (struct
  let desc = "any"
  let make r = AnyT r
end)

module VoidT = Primitive (struct
  let desc = "undefined"
  let make r = VoidT r
end)

module NullT = Primitive (struct
  let desc = "null"
  let make r = NullT r
end)

(** Type variables are unknowns, and we are ultimately interested in constraints
    on their solutions for type inference.

    Type variables form nodes in a "union-find" forest: each tree denotes a set
    of type variables that are considered by the type system to be equivalent.

    There are two kinds of nodes: Goto nodes and Root nodes.

    - All Goto nodes of a tree point, directly or indirectly, to the Root node
    of the tree.
    - A Root node holds the actual non-trivial state of a tvar, represented by a
    root structure (see below).
**)
type node =
| Goto of ident
| Root of root

(** A root structure carries the actual non-trivial state of a tvar, and
    consists of:

    - rank, which is a quantity roughly corresponding to the longest chain of
    gotos pointing to the tvar. It's an implementation detail of the unification
    algorithm that simply has to do with efficiently finding the root of a tree.
    We merge a tree with another tree by converting the root with the lower rank
    to a goto node, and making it point to the root with the higher rank. See
    http://en.wikipedia.org/wiki/Disjoint-set_data_structure for more details on
    this data structure and supported operations.

    - constraints, which carry type information that narrows down the possible
    solutions of the tvar (see below).  **)

and root = {
  rank: int;
  constraints: constraints;
}

(** Constraints carry type information that narrows down the possible solutions
    of tvar, and are of two kinds:

    - A Resolved constraint contains a concrete type that is considered by the
    type system to be the solution of the tvar carrying the constraint. In other
    words, the tvar is equivalent to this concrete type in all respects.

    - Unresolved constraints contain bounds that carry both concrete types and
    other tvars as upper and lower bounds (see below).
**)

and constraints =
| Resolved of Type.t
| Unresolved of bounds

(** The bounds structure carries the evolving constraints on the solution of an
    unresolved tvar.

    - upper and lower hold concrete upper and lower bounds, respectively. At any
    point in analysis the aggregate lower bound of a tvar is (conceptually) the
    union of the concrete types in lower, and the aggregate upper bound is
    (conceptually) the intersection of the concrete types in upper. (Upper and
    lower are maps, with the types as keys, and trace information as values.)

    - lowertvars and uppertvars hold tvars which are also (latent) lower and
    upper bounds, respectively. See the __flow function for how these structures
    are populated and operated on.  Here the map keys are tvar ids, with trace
    info as values.
**)
and bounds = {
  mutable lower: trace TypeMap.t;
  mutable upper: trace TypeMap.t;
  mutable lowertvars: trace IMap.t;
  mutable uppertvars: trace IMap.t;
}

(* Extract bounds from a node. *)
(** WARNING: This function is unsafe, since not all nodes are roots, and not all
    roots are unresolved. Use this function only when you are absolutely sure
    that a node is an unresolved root: this is guaranteed to be the case when
    the type variable it denotes is never involved in unification. **)
let bounds_of_unresolved_root node =
  match node with
  | Root { constraints = Unresolved bounds; _ } -> bounds
  | _ -> failwith "expected unresolved root"

let new_bounds () = {
  lower = TypeMap.empty;
  upper = TypeMap.empty;
  lowertvars = IMap.empty;
  uppertvars = IMap.empty;
}

let new_unresolved_root () =
  Root { rank = 0; constraints = Unresolved (new_bounds ()) }

let copy_bounds = function
  | { lower; upper; lowertvars; uppertvars; } ->
    { lower; upper; lowertvars; uppertvars; }

let copy_node node = match node with
  | Root { rank; constraints = Unresolved bounds } ->
    Root { rank; constraints = Unresolved (copy_bounds bounds) }
  | _ -> node

(***************************************)

(* scopes *)
(* these are basically owned by Env_js, but are here
   to break circularity between Env_js and Flow_js
 *)

module Scope = struct

  (* entries for vars/lets, consts and types *)
  module Entry = struct

    type state = Undeclared | Declared | Initialized

    let string_of_state = function
    | Undeclared -> "Undeclared"
    | Declared -> "Declared"
    | Initialized -> "Initialized"

    type value_kind =
      | Const
      (* Some let bindings are explicit (like you wrote let x = 123) and some
       * are implicit (like class declarations). For implicit lets, we should
       * track why this is a let binding for better error messages *)
      | Let of implicit_let_kinds option
      | Var

    and implicit_let_kinds =
      | ClassNameBinding
      | CatchParamBinding
      | FunctionBinding

    let string_of_value_kind = function
    | Const -> "const"
    | Let None -> "let"
    | Let (Some ClassNameBinding) -> "class"
    | Let (Some CatchParamBinding) -> "catch"
    | Let (Some FunctionBinding) -> "function"
    | Var -> "var"

    type value_binding = {
      kind: value_kind;
      value_state: state;
      value_loc: Loc.t option;
      specific: Type.t;
      general: Type.t;
    }

    type type_binding = {
      type_state: state;
      type_loc: Loc.t option;
      _type: Type.t;
    }

    type t =
    | Value of value_binding
    | Type of type_binding

    (* constructors *)
    let new_value kind state specific general value_loc =
      Value {
        kind;
        value_state = state;
        value_loc;
        specific;
        general
      }

    let new_const ?loc ?(state=Undeclared) t = new_value Const state t t loc

    let new_let ?loc ?(state=Undeclared) ?implicit t =
      new_value (Let implicit) state t t loc

    let new_var ?loc ?(state=Undeclared) ?specific general =
      let specific = match specific with Some t -> t | None -> general in
      new_value Var state specific general loc

    let new_type ?loc ?(state=Undeclared) _type =
      Type {
        type_state = state;
        type_loc = loc;
        _type
      }

    (* accessors *)
    let loc = function
    | Value v -> v.value_loc
    | Type t -> t.type_loc

    let declared_type = function
    | Value v -> v.general
    | Type t -> t._type

    let actual_type = function
    | Value v -> v.specific
    | Type t -> t._type

    let string_of_kind = function
    | Value v -> string_of_value_kind v.kind
    | Type _ -> "type"

    (* Given a name, an entry, and a function for making a new
       specific type from a Var entry's current general type,
       return a new non-internal Value entry with specific type replaced,
       or the existing entry.
       Note: we continue to need the is_internal trap here,
       due to our modeling of this and super as flow-sensitive vars
       in derived constructors.
     *)
    let havoc ?name make_specific name entry =
      match entry with
      | Value v ->
        if is_internal_name name then entry
        else Value { v with specific = make_specific v.general }
      | Type _ -> entry

    let is_lex = function
      | Type _ -> false
      | Value v ->
        match v.kind with
        | Const -> true
        | Let _ -> true
        | _ -> false
  end

  (* keys for refinements *)
  module Key = struct

    type proj = Prop of string | Elem of t
    and t = string * proj list

    let rec string_of_key (base, projs) =
      base ^ String.concat "" (
        (List.rev projs) |> List.map (function
          | Prop name -> spf ".%s" name
          | Elem expr -> spf "[%s]" (string_of_key expr)
        ))

    (* true if the given key uses the given property name *)
    let rec uses_propname propname (base, proj) =
      proj_uses_propname propname proj

    (* true if the given projection list uses the given property name *)
    and proj_uses_propname propname = function
    | Prop name :: tail ->
      name = propname || proj_uses_propname propname tail
    | Elem key :: tail ->
      uses_propname propname key || proj_uses_propname propname tail
    | [] ->
      false

    let compare = Pervasives.compare

  end

  module KeySet : Set.S with type elt = Key.t
  = Set.Make(Key)

  module KeyMap : MapSig with type key = Key.t
  = MyMap(Key)

  (* a var scope corresponds to a runtime activation,
     e.g. a function. *)
  type function_kind = Ordinary | Async | Generator

  (* var and lexical scopes differ in hoisting behavior
     and auxiliary properties *)
  (* TODO lexical scope support *)
  type kind =
  | VarScope of function_kind
  | LexScope

  type refi_binding = {
    refi_loc: Loc.t option;
    refined: Type.t;
    original: Type.t;
  }

  (* a scope is a mutable binding table, plus kind and attributes *)
  (* TODO add in-scope type variable binding table *)
  type t = {
    kind: kind;
    mutable entries: Entry.t SMap.t;
    mutable refis: refi_binding KeyMap.t
  }

  let fresh_impl kind = {
    kind;
    entries = SMap.empty;
    refis = KeyMap.empty;
  }

  (* return a fresh scope of the most common kind (var) *)
  let fresh ?(kind=Ordinary) () =
    fresh_impl (VarScope kind)

  (* return a fresh lexical scope *)
  let fresh_lex () = fresh_impl LexScope

  (* clone a scope (snapshots mutable entries) *)
  let clone { kind; entries; refis } = { kind; entries; refis }

  (* use passed f to iterate over all scope entries *)
  let iter_entries f scope =
    SMap.iter f scope.entries

  (* use passed f to update all scope entries *)
  let update_entries f scope =
    scope.entries <- SMap.mapi f scope.entries

  (* add entry to scope *)
  let add_entry name entry scope =
    scope.entries <- SMap.add name entry scope.entries

  (* remove entry from scope *)
  let remove_entry name scope =
    scope.entries <- SMap.remove name scope.entries

  (* get entry from scope, or None *)
  let get_entry name scope =
    SMap.get name scope.entries

  (* use passed f to update all scope refis *)
  let update_refis f scope =
    scope.refis <- KeyMap.mapi f scope.refis

  (* add refi to scope *)
  let add_refi key refi scope =
    scope.refis <- KeyMap.add key refi scope.refis

  (* remove entry from scope *)
  let remove_refi key scope =
    scope.refis <- KeyMap.remove key scope.refis

  (* get entry from scope, or None *)
  let get_refi name scope =
    KeyMap.get name scope.refis

  (* helper: filter all refis whose expressions involve the given name *)
  let filter_refis_using_propname propname refis =
    refis |> KeyMap.filter (fun key _ ->
      not (Key.uses_propname propname key)
    )

  (* havoc a scope:
     - if name is not passed, clear all refis. if passed, clear
       any refis whose expressions involve name
     - make_specific makes a new specific type from a general type.
     if passed, havoc all non-internal var entries using it
   *)
  let havoc ?name ?make_specific scope =
    scope.refis <- (match name with
    | Some name -> scope.refis |> (filter_refis_using_propname name)
    | None -> KeyMap.empty);
    match make_specific with
    | Some f -> scope |> update_entries (Entry.havoc ~name f)
    | None -> ()

  let is_lex scope =
    match scope.kind with
    | LexScope -> true
    | _ -> false
end

(***************************************)

(* type context *)

type stack = int list

type context = {
  file: string;
  _module: string;
  checked: bool;
  weak: bool;

  (* required modules, and map to their locations *)
  mutable required: SSet.t;
  mutable require_loc: Loc.t SMap.t;
  mutable module_exports_type: module_exports_type;

  (* map from tvar ids to nodes (type info structures) *)
  mutable graph: node IMap.t;

  (* obj types point to mutable property maps *)
  mutable property_maps: Type.properties IMap.t;

  (* map from closure ids to env snapshots *)
  mutable closures: (stack * Scope.t list) IMap.t;

  (* map from module names to their types *)
  mutable modulemap: Type.t SMap.t;

  mutable errors: Errors_js.ErrorSet.t;
  mutable globals: SSet.t;

  mutable error_suppressions: Errors_js.ErrorSuppressions.t;

  type_table: (Loc.t, Type.t) Hashtbl.t;
  annot_table: (Loc.t, Type.t) Hashtbl.t;
}

and module_exports_type =
  | CommonJSModule of Loc.t option
  | ESModule

(* create a new context structure.
   Flow_js.fresh_context prepares for actual use.
 *)
let new_context ?(checked=false) ?(weak=false) ~file ~_module = {
  file;
  _module;
  checked;
  weak;

  required = SSet.empty;
  require_loc = SMap.empty;
  module_exports_type = CommonJSModule(None);

  graph = IMap.empty;
  closures = IMap.empty;
  property_maps = IMap.empty;
  modulemap = SMap.empty;

  errors = Errors_js.ErrorSet.empty;
  globals = SSet.empty;

  error_suppressions = Errors_js.ErrorSuppressions.empty;

  type_table = Hashtbl.create 0;
  annot_table = Hashtbl.create 0;
}



(********************************************************************)

(* def types vs. use types *)
let is_use = function
  | CallT _
  | MethodT _
  | SetPropT _
  | GetPropT _
  | SetElemT _
  | GetElemT _
  | ConstructorT _
  | SuperT _
  | ExtendsT _
  | AdderT _
  | AndT _
  | OrT _
  | ComparatorT _
  | PredicateT _
  | EqT _
  | SpecializeT _
  | LookupT _
  | ObjAssignT _
  | ObjFreezeT _
  | ObjRestT _
  | ObjSealT _
  | ObjTestT _
  | UnifyT _
  | GetKeysT _
  | HasKeyT _
  | ElemT _
  | ConcreteT _
  | ConcretizeT _
  | BecomeT _
  | CJSRequireT _
  | ImportModuleNsT _
  | ImportTypeT _
  | ImportTypeofT _
  | CJSExtractNamedExportsT _
  | SetNamedExportsT _
  | SetCJSExportT _
    -> true

  | _ -> false


(********************************************************************)

(* printing *)

let string_of_ctor = function
  | OpenT _ -> "OpenT"
  | NumT _ -> "NumT"
  | StrT _ -> "StrT"
  | BoolT _ -> "BoolT"
  | UndefT _ -> "UndefT"
  | MixedT _ -> "MixedT"
  | AnyT _ -> "AnyT"
  | NullT _ -> "NullT"
  | VoidT _ -> "VoidT"
  | FunT _ -> "FunT"
  | PolyT _ -> "PolyT"
  | BoundT _ -> "BoundT"
  | ExistsT _ -> "ExistsT"
  | ObjT _ -> "ObjT"
  | ArrT _ -> "ArrT"
  | ClassT _ -> "ClassT"
  | InstanceT _ -> "InstanceT"
  | SummarizeT _ -> "SummarizeT"
  | SuperT _ -> "SuperT"
  | ExtendsT _ -> "ExtendsT"
  | CallT _ -> "CallT"
  | MethodT _ -> "MethodT"
  | SetPropT _ -> "SetPropT"
  | GetPropT _ -> "GetPropT"
  | SetElemT _ -> "SetElemT"
  | GetElemT _ -> "GetElemT"
  | ConstructorT _ -> "ConstructorT"
  | AdderT _ -> "AdderT"
  | ComparatorT _ -> "ComparatorT"
  | TypeT _ -> "TypeT"
  | AnnotT _ -> "AnnotT"
  | BecomeT _ -> "BecomeT"
  | OptionalT _ -> "OptionalT"
  | RestT _ -> "RestT"
  | PredicateT _ -> "PredicateT"
  | EqT _ -> "EqT"
  | AndT _ -> "AndT"
  | OrT _ -> "OrT"
  | NotT _ -> "NotT"
  | SpecializeT _ -> "SpecializeT"
  | TypeAppT _ -> "TypeAppT"
  | MaybeT _ -> "MaybeT"
  | IntersectionT _ -> "IntersectionT"
  | UnionT _ -> "UnionT"
  | LookupT _ -> "LookupT"
  | UnifyT _ -> "UnifyT"
  | ObjAssignT _ -> "ObjAssignT"
  | ObjFreezeT _ -> "ObjFreezeT"
  | ObjRestT _ -> "ObjRestT"
  | ObjSealT _ -> "ObjSealT"
  | ObjTestT _ -> "ObjTestT"
  | UpperBoundT _ -> "UpperBoundT"
  | LowerBoundT _ -> "LowerBoundT"
  | AnyObjT _ -> "AnyObjT"
  | AnyFunT _ -> "AnyFunT"
  | ShapeT _ -> "ShapeT"
  | DiffT _ -> "DiffT"
  | KeysT _ -> "KeysT"
  | SingletonStrT _ -> "SingletonStrT"
  | SingletonNumT _ -> "SingletonNumT"
  | SingletonBoolT _ -> "SingletonBoolT"
  | GetKeysT _ -> "GetKeysT"
  | HasKeyT _ -> "HasKeyT"
  | ElemT _ -> "ElemT"
  | ConcretizeT _ -> "ConcretizeT"
  | ConcreteT _ -> "ConcreteT"
  | SpeculativeMatchFailureT _ -> "SpeculativeMatchFailureT"
  | ImportModuleNsT _ -> "ImportModuleNsT"
  | ImportTypeT _ -> "ImportTypeT"
  | ImportTypeofT _ -> "ImportTypeofT"
  | ModuleT _ -> "ModuleT"
  | CJSRequireT _ -> "CJSRequireT"
  | CJSExtractNamedExportsT _ -> "CJSExtractNamedExportsT"
  | SetNamedExportsT _ -> "SetNamedExportsT"
  | SetCJSExportT _ -> "SetCJSExportT"

(* Usually types carry enough information about the "reason" for their
   existence (e.g., position in code, introduction/elimination rules in
   the type system), so printing the reason provides a good idea of what the
   type means to the programmer. *)

let rec reason_of_t = function
  (* note: keep in order of decls in constraint_js *)

  | OpenT (reason,_)

  | NumT (reason, _)
  | StrT (reason, _)
  | BoolT (reason, _)
  | UndefT reason
  | MixedT reason
  | AnyT reason
  | NullT reason
  | VoidT reason

  | FunT (reason,_,_,_)
      -> reason

  | PolyT (_,t) ->
      prefix_reason "polymorphic type: " (reason_of_t t)
  | BoundT typeparam ->
      typeparam.reason
  | ExistsT reason ->
      reason

  | ObjT (reason,_)
  | ArrT (reason,_,_)
      -> reason

  | ClassT t ->
      prefix_reason "class type: " (reason_of_t t)

  | InstanceT (reason,_,_,_)
  | SuperT (reason,_)

  | CallT (reason, _)

  | MethodT (reason,_,_)
  | SetPropT (reason,_,_)
  | GetPropT (reason,_,_)

  | SetElemT (reason,_,_)
  | GetElemT (reason,_,_)

  | ConstructorT (reason,_,_)

  | AdderT (reason,_,_)
  | ComparatorT (reason,_)

  | AndT (reason, _, _)
  | OrT (reason, _, _)
  | NotT (reason, _)

  | TypeT (reason,_)
  | BecomeT (reason, _)
      -> reason

  | AnnotT (_, assume_t) ->
      reason_of_t assume_t

  | ExtendsT (_,_,t) ->
      prefix_reason "extends " (reason_of_t t)

  | OptionalT t ->
      prefix_reason "optional " (reason_of_t t)

  | RestT t ->
      prefix_reason "rest array of " (reason_of_t t)

  | PredicateT (pred,t) -> reason_of_t t

  | EqT (reason, t) ->
      reason

  | SpecializeT(reason,_,_,_)
      -> reason

  | TypeAppT(t,_)
      -> prefix_reason "type application of " (reason_of_t t)

  | MaybeT t ->
      prefix_reason "?" (reason_of_t t)

  | IntersectionT (reason, _) ->
      reason

  | UnionT (reason, _) ->
      reason

  | LookupT(reason, _, _, _, _) ->
      reason

  | UnifyT(_,t) ->
      reason_of_t t

  | ObjAssignT (reason, _, _, _, _)
  | ObjFreezeT (reason, _)
  | ObjRestT (reason, _, _)
  | ObjSealT (reason, _)
  | ObjTestT (reason, _, _)
    ->
      reason

  | UpperBoundT (t)
  | LowerBoundT (t)
      -> reason_of_t t

  | AnyObjT reason ->
      reason
  | AnyFunT reason ->
      reason

  | ShapeT (t)
      -> reason_of_t t
  | DiffT (t, _)
      -> reason_of_t t

  | KeysT (reason, _)
  | SingletonStrT (reason, _)
  | SingletonNumT (reason, _)
  | SingletonBoolT (reason, _) -> reason

  | GetKeysT (reason, _) -> reason
  | HasKeyT (reason, _) -> reason

  | ElemT (reason, _, _) -> reason

  | ConcretizeT (t, _, _, _) -> reason_of_t t
  | ConcreteT (t) -> reason_of_t t

  | SpeculativeMatchFailureT (reason, _, _) -> reason

  | SummarizeT (reason, t) -> reason

  | ModuleT (reason, _) -> reason

  | CJSRequireT (reason, _) -> reason
  | ImportModuleNsT (reason, _) -> reason
  | ImportTypeT (reason, _) -> reason
  | ImportTypeofT (reason, _) -> reason
  | CJSExtractNamedExportsT (reason, _, _) -> reason
  | SetNamedExportsT (reason, _, _) -> reason
  | SetCJSExportT (reason, _, _) -> reason

and string_of_predicate = function
  | AndP (p1,p2) ->
      (string_of_predicate p1) ^ " && " ^ (string_of_predicate p2)
  | OrP (p1,p2) ->
      (string_of_predicate p1) ^ " || " ^ (string_of_predicate p2)
  | NotP p -> "not " ^ (string_of_predicate p)
  | LeftP (b, t) ->
      spf "left operand of %s with right operand = %s"
        (string_of_binary_test b) (desc_of_t t)
  | RightP (b, t) ->
      spf "right operand of %s with left operand = %s"
        (string_of_binary_test b) (desc_of_t t)
  | ExistsP -> "truthy"
  | IsP s -> s

and string_of_binary_test = function
  | Instanceof -> "instanceof"
  | SentinelProp key -> "sentinel prop " ^ key

and loc_of_predicate = function
  | AndP (p1,p2)
  | OrP (p1,p2)
    -> loc_of_predicate p1

  | NotP p
    -> loc_of_predicate p

  | LeftP (_, t)
  | RightP (_, t)
    -> loc_of_t t

  | ExistsP
  | IsP _
    -> Loc.none (* TODO!!!!!!!!!!!! *)

and streason_of_t t = string_of_reason (reason_of_t t)

and desc_of_t t = desc_of_reason (reason_of_t t)

and loc_of_t t = loc_of_reason (reason_of_t t)

(* TODO make a type visitor *)
let rec mod_reason_of_t f = function

  | OpenT (reason, t) -> OpenT (f reason, t)
  | NumT (reason, t) -> NumT (f reason, t)
  | StrT (reason, t) -> StrT (f reason, t)
  | BoolT (reason, t) -> BoolT (f reason, t)
  | UndefT reason -> UndefT (f reason)
  | MixedT reason -> MixedT (f reason)
  | AnyT reason -> AnyT (f reason)
  | NullT reason -> NullT (f reason)
  | VoidT reason -> VoidT (f reason)

  | FunT (reason, s, p, ft) -> FunT (f reason, s, p, ft)
  | PolyT (plist, t) -> PolyT (plist, mod_reason_of_t f t)
  | BoundT { reason; name; bound; polarity } ->
    BoundT { reason = f reason; name; bound; polarity }
  | ExistsT reason -> ExistsT (f reason)
  | ObjT (reason, ot) -> ObjT (f reason, ot)
  | ArrT (reason, t, ts) -> ArrT (f reason, t, ts)

  | ClassT t -> ClassT (mod_reason_of_t f t)
  | InstanceT (reason, st, su, inst) -> InstanceT (f reason, st, su, inst)
  | SuperT (reason, inst) -> SuperT (f reason, inst)
  | ExtendsT (ts, t, tc) -> ExtendsT (ts, t, mod_reason_of_t f tc)

  | CallT (reason, ft) -> CallT (f reason, ft)

  | MethodT (reason, name, ft) -> MethodT(f reason, name, ft)
  | SetPropT (reason, n, t) -> SetPropT (f reason, n, t)
  | GetPropT (reason, n, t) -> GetPropT (f reason, n, t)

  | SetElemT (reason, it, et) -> SetElemT (f reason, it, et)
  | GetElemT (reason, it, et) -> GetElemT (f reason, it, et)

  | ConstructorT (reason, ts, t) -> ConstructorT (f reason, ts, t)

  | AdderT (reason, rt, lt) -> AdderT (f reason, rt, lt)
  | ComparatorT (reason, t) -> ComparatorT (f reason, t)

  | TypeT (reason, t) -> TypeT (f reason, t)
  | AnnotT (assert_t, assume_t) ->
      AnnotT (mod_reason_of_t f assert_t, mod_reason_of_t f assume_t)
  | BecomeT (reason, t) -> BecomeT (f reason, t)

  | OptionalT t -> OptionalT (mod_reason_of_t f t)

  | RestT t -> RestT (mod_reason_of_t f t)

  | PredicateT (pred, t) -> PredicateT (pred, mod_reason_of_t f t)

  | EqT (reason, t) -> EqT (f reason, t)

  | AndT (reason, t1, t2) -> AndT (f reason, t1, t2)
  | OrT (reason, t1, t2) -> OrT (f reason, t1, t2)
  | NotT (reason, t) -> NotT (f reason, t)

  | SpecializeT(reason, cache, ts, t) -> SpecializeT (f reason, cache, ts, t)

  | TypeAppT (t, ts) -> TypeAppT (mod_reason_of_t f t, ts)

  | MaybeT t -> MaybeT (mod_reason_of_t f t)

  | IntersectionT (reason, ts) -> IntersectionT (f reason, ts)

  | UnionT (reason, ts) -> UnionT (f reason, ts)

  | LookupT (reason, r2, ts, x, t) -> LookupT (f reason, r2, ts, x, t)

  | UnifyT (t, t2) -> UnifyT (mod_reason_of_t f t, mod_reason_of_t f t2)

  | ObjAssignT (reason, t, t2, filter, resolve) ->
      ObjAssignT (f reason, t, t2, filter, resolve)
  | ObjFreezeT (reason, t) -> ObjFreezeT (f reason, t)
  | ObjRestT (reason, t, t2) -> ObjRestT (f reason, t, t2)
  | ObjSealT (reason, t) -> ObjSealT (f reason, t)
  | ObjTestT (reason, t1, t2) -> ObjTestT (f reason, t1, t2)

  | UpperBoundT t -> UpperBoundT (mod_reason_of_t f t)
  | LowerBoundT t -> LowerBoundT (mod_reason_of_t f t)

  | AnyObjT reason -> AnyObjT (f reason)
  | AnyFunT reason -> AnyFunT (f reason)

  | ShapeT t -> ShapeT (mod_reason_of_t f t)
  | DiffT (t1, t2) -> DiffT (mod_reason_of_t f t1, t2)

  | KeysT (reason, t) -> KeysT (f reason, t)
  | SingletonStrT (reason, t) -> SingletonStrT (f reason, t)
  | SingletonNumT (reason, t) -> SingletonNumT (f reason, t)
  | SingletonBoolT (reason, t) -> SingletonBoolT (f reason, t)

  | GetKeysT (reason, t) -> GetKeysT (f reason, t)
  | HasKeyT (reason, t) -> HasKeyT (f reason, t)

  | ElemT (reason, t, t2) -> ElemT (f reason, t, t2)

  | ConcretizeT (t1, ts1, ts2, t2) ->
      ConcretizeT (mod_reason_of_t f t1, ts1, ts2, t2)
  | ConcreteT t -> ConcreteT (mod_reason_of_t f t)

  | SpeculativeMatchFailureT (reason, t1, t2) ->
      SpeculativeMatchFailureT (f reason, t1, t2)

  | SummarizeT (reason, t) -> SummarizeT (f reason, t)

  | ModuleT (reason, exports) -> ModuleT (f reason, exports)

  | CJSRequireT (reason, t) -> CJSRequireT (f reason, t)
  | ImportModuleNsT (reason, t) -> ImportModuleNsT (f reason, t)
  | ImportTypeT (reason, t) -> ImportTypeT (f reason, t)
  | ImportTypeofT (reason, t) -> ImportTypeofT (f reason, t)

  | CJSExtractNamedExportsT (reason, t1, t2) -> CJSExtractNamedExportsT (f reason, t1, t2)
  | SetNamedExportsT (reason, tmap, t_out) -> SetNamedExportsT(f reason, tmap, t_out)
  | SetCJSExportT (reason, t, t_out) -> SetCJSExportT (f reason, t, t_out)

(* replace a type's pos with one taken from a reason *)
let repos_t_from_reason r t =
  mod_reason_of_t (repos_reason (loc_of_reason r)) t

(* return a type copy with reason modified using second, operational reason *)
let to_op_reason op_reason t =
  mod_reason_of_t (fun r ->
    let d = spf "%s (%s)" (desc_of_reason r) (desc_of_reason op_reason) in
    mk_reason d (loc_of_reason op_reason)
  ) t

(* replace a type's reason in its entirety *)
let swap_reason t r =
  mod_reason_of_t (fun _ -> r) t

(* type comparison mod reason *)
let reasonless_compare t t' =
  if t == t' then 0 else
  Pervasives.compare t (swap_reason t' (reason_of_t t))

let name_prefix_of_t = function
  | RestT _ -> "..."
  | _ -> ""

let name_suffix_of_t = function
  | OptionalT _ -> "?"
  | _ -> ""

let parameter_name cx n t =
  (name_prefix_of_t t) ^ n ^ (name_suffix_of_t t)

type enclosure_t =
    EnclosureNone
  | EnclosureUnion
  | EnclosureIntersect
  | EnclosureParam
  | EnclosureMaybe
  | EnclosureAppT
  | EnclosureRet

let parenthesize t_str enclosure triggers =
  if List.mem enclosure triggers
  then "(" ^ t_str ^ ")"
  else t_str

(* general-purpose type printer. not the cleanest visitor in the world,
   but reasonably general. override gets a chance to print the incoming
   type first. if it passes, the bulk of printable types are formatted
   in a reasonable way. fallback is sent the rest. enclosure drives
   delimiter choice. see e.g. dump_t and string_of_t for callers.
 *)
let rec type_printer override fallback enclosure cx t =
  let pp = type_printer override fallback in
  match override cx t with
  | Some s -> s
  | None ->
    match t with
    | BoundT typeparam -> typeparam.name

    | SingletonStrT (_, s) -> spf "'%s'" s
    | SingletonNumT (_, (_, raw)) -> raw
    | SingletonBoolT (_, b) -> string_of_bool b

    (* reasons for VoidT use "undefined" for more understandable error output.
       For parsable types we need to use "void" though, thus overwrite it. *)
    | VoidT _ -> "void"

    | FunT (_,_,_,{params_tlist = ts; params_names = pns; return_t = t; _}) ->
        let pns =
          match pns with
          | Some pns -> pns
          | None -> List.map (fun _ -> "_") ts in
        let type_s = spf "(%s) => %s"
          (List.map2 (fun n t ->
              (parameter_name cx n t) ^
              ": "
              ^ (pp EnclosureParam cx t)
            ) pns ts
           |> String.concat ", "
          )
          (pp EnclosureNone cx t) in
        parenthesize type_s enclosure [EnclosureUnion; EnclosureIntersect]

    | ObjT (_, {props_tmap = flds; dict_t; _}) ->
        let props =
          IMap.find_unsafe flds cx.property_maps
           |> SMap.elements
           |> List.filter (fun (x,_) -> not (Reason_js.is_internal_name x))
           |> List.rev
           |> List.map (fun (x,t) -> x ^ ": " ^ (pp EnclosureNone cx t) ^ ";")
           |> String.concat " "
        in
        let indexer =
          (match dict_t with
          | Some { dict_name; key; value } ->
              let indexer_prefix =
                if props <> ""
                then " "
                else ""
              in
              let dict_name = match dict_name with
                | None -> "_"
                | Some name -> name
              in
              (spf "%s[%s: %s]: %s;"
                indexer_prefix
                dict_name
                (pp EnclosureNone cx key)
                (pp EnclosureNone cx value)
              )
          | None -> "")
        in
        spf "{%s%s}" props indexer

    | ArrT (_, t, ts) ->
        (*(match ts with
        | [] -> *)spf "Array<%s>" (pp EnclosureNone cx t)
        (*| _ -> spf "[%s]"
                  (ts
                    |> List.map (pp cx EnclosureNone)
                    |> String.concat ", "))*)

    | InstanceT (reason,static,super,instance) ->
        desc_of_reason reason (* nominal type *)

    | TypeAppT (c,ts) ->
        let type_s =
          spf "%s <%s>"
            (pp EnclosureAppT cx c)
            (ts
              |> List.map (pp EnclosureNone cx)
              |> String.concat ", "
            )
        in
        parenthesize type_s enclosure [EnclosureMaybe]

    | MaybeT t ->
        spf "?%s" (pp EnclosureMaybe cx t)

    | PolyT (xs,t) ->
        let type_s =
          spf "<%s> %s"
            (xs
              |> List.map (fun param -> param.name)
              |> String.concat ", "
            )
            (pp EnclosureNone cx t)
        in
        parenthesize type_s enclosure [EnclosureAppT; EnclosureMaybe]

    | IntersectionT (_, ts) ->
        let type_s =
          (ts
            |> List.map (pp EnclosureIntersect cx)
            |> String.concat " & "
          ) in
        parenthesize type_s enclosure [EnclosureUnion; EnclosureMaybe]

    | UnionT (_, ts) ->
        let type_s =
          (ts
            |> List.map (pp EnclosureUnion cx)
            |> String.concat " | "
          ) in
        parenthesize type_s enclosure [EnclosureIntersect; EnclosureMaybe]

    (* The following types are not syntax-supported in all cases *)
    | RestT t ->
        let type_s =
          spf "Array<%s>" (pp EnclosureNone cx t) in
        if enclosure == EnclosureParam
        then type_s
        else "..." ^ type_s

    | OptionalT t ->
        let type_s = pp EnclosureNone cx t in
        if enclosure == EnclosureParam
        then type_s
        else "=" ^ type_s

    | AnnotT (_, t) -> pp EnclosureNone cx t
    | KeysT (_, t) -> spf "$Keys<%s>" (pp EnclosureNone cx t)
    | ShapeT t -> spf "$Shape<%s>" (pp EnclosureNone cx t)

    (* The following types are not syntax-supported *)
    | ClassT t ->
        spf "[class: %s]" (pp EnclosureNone cx t)

    | TypeT (_, t) ->
        spf "[type: %s]" (pp EnclosureNone cx t)

    | BecomeT (_, t) ->
        spf "[become: %s]" (pp EnclosureNone cx t)

    | LowerBoundT t ->
        spf "$Subtype<%s>" (pp EnclosureNone cx t)

    | UpperBoundT t ->
        spf "$Supertype<%s>" (pp EnclosureNone cx t)

    | AnyObjT _ ->
        "Object"

    | AnyFunT _ ->
        "Function"

    | t ->
        fallback t

(* pretty printer *)
let string_of_t_ =
  let override cx t = match t with
    | OpenT (r, id) -> Some (spf "TYPE_%d" id)
    | NumT _
    | StrT _
    | BoolT _
    | UndefT _
    | MixedT _
    | AnyT _
    | NullT _ -> Some (desc_of_reason (reason_of_t t))
    | _ -> None
  in
  let fallback t =
    assert_false (spf "Missing printer for %s" (string_of_ctor t))
  in
  fun enclosure cx t ->
    type_printer override fallback enclosure cx t

let string_of_t =
  string_of_t_ EnclosureNone

let string_of_param_t =
  string_of_t_ EnclosureParam

(****************** json ******************)

module Json = Hh_json

let string_of_pred_ctor = function
  | AndP _ -> "AndP"
  | OrP _ -> "OrP"
  | NotP _ -> "NotP"
  | LeftP _ -> "LeftP"
  | RightP _ -> "RightP"
  | ExistsP -> "ExistsP"
  | IsP _ -> "IsP"

let string_of_binary_test_ctor = function
  | Instanceof -> "Instanceof"
  | SentinelProp _ -> "SentinelProp"

type json_cx = {
  stack: ISet.t;
  depth: int;
  cx: context;
}

let check_depth continuation json_cx =
  let depth = json_cx.depth - 1 in
  if depth < 0
  then fun _ -> Json.JNull
  else continuation { json_cx with depth; }

let rec _json_of_t json_cx = check_depth _json_of_t_impl json_cx
and _json_of_t_impl json_cx t = Json.(
  JAssoc ([
    "reason", json_of_reason (reason_of_t t);
    "kind", JString (string_of_ctor t)
  ] @
  match t with
  | OpenT (_, id) -> [
      "id", JInt id
    ] @
    if ISet.mem id json_cx.stack then []
    else [
      "node", json_of_node json_cx id
    ]

  | NumT (_, lit) ->
    begin match lit with
    | Literal (_, raw) -> ["literal", JString raw]
    | Truthy
    | Falsy
    | AnyLiteral -> []
    end

  | StrT (_, lit) ->
    begin match lit with
    | Literal s -> ["literal", JString s]
    | Truthy
    | Falsy
    | AnyLiteral -> []
    end

  | BoolT (_, b) ->
    (match b with
      | Some b -> ["literal", JBool b]
      | None -> [])

  | UndefT _
  | MixedT _
  | AnyT _
  | NullT _
  | VoidT _ ->
    []

  | FunT (_, static, proto, funtype) -> [
      "static", _json_of_t json_cx static;
      "prototype", _json_of_t json_cx proto;
      "funType", json_of_funtype json_cx funtype
    ]

  | ObjT (_, objtype) -> [
      "type", json_of_objtype json_cx objtype
    ]

  | ArrT (_, elemt, tuplet) -> [
      "elemType", _json_of_t json_cx elemt;
      "tupleType", JList (List.map (_json_of_t json_cx) tuplet)
    ]

  | ClassT t -> [
      "type", _json_of_t json_cx t
    ]

  | InstanceT (_, static, super, instance) -> [
      "static", _json_of_t json_cx static;
      "super", _json_of_t json_cx super;
      "instance", json_of_insttype json_cx instance
    ]

  | OptionalT t
  | RestT t -> [
      "type", _json_of_t json_cx t
    ]

  | PolyT (tparams, t) -> [
      "typeParams", JList (List.map (json_of_typeparam json_cx) tparams);
      "type", _json_of_t json_cx t
    ]

  | TypeAppT (t, targs) -> [
      "typeArgs", JList (List.map (_json_of_t json_cx) targs);
      "type", _json_of_t json_cx t
    ]

  | BoundT tparam -> [
      "typeParam", json_of_typeparam json_cx tparam
    ]

  | ExistsT tparam ->
    []

  | MaybeT t -> [
      "type", _json_of_t json_cx t
    ]

  | IntersectionT (_, ts)
  | UnionT (_, ts) -> [
      "types", JList (List.map (_json_of_t json_cx) ts)
    ]

  | UpperBoundT t
  | LowerBoundT t -> [
      "type", _json_of_t json_cx t
    ]

  | AnyObjT _
  | AnyFunT _ ->
    []

  | ShapeT t -> [
      "type", _json_of_t json_cx t
    ]

  | DiffT (t1, t2) -> [
      "type1", _json_of_t json_cx t1;
      "type2", _json_of_t json_cx t2
    ]

  | KeysT (_, t) -> [
      "type", _json_of_t json_cx t
    ]

  | SingletonStrT (_, s) -> [
      "literal", JString s
    ]

  | SingletonNumT (_, (_, raw)) -> [
      "literal", JString raw
    ]

  | SingletonBoolT (_, b) -> [
      "literal", JBool b
    ]

  | TypeT (_, t) -> [
      "result", _json_of_t json_cx t
    ]

  | AnnotT (t1, t2) -> [
      "assert", _json_of_t json_cx t1;
      "assume", _json_of_t json_cx t2
    ]

  | BecomeT (_, t) -> [
      "result", _json_of_t json_cx t
    ]

  | SpeculativeMatchFailureT (_, attempt, target) -> [
      "attemptType", _json_of_t json_cx attempt;
      "targetType", _json_of_t json_cx target
    ]

  | ModuleT (_, {exports_tmap; cjs_export;}) -> [
      "namedExports",
      (let tmap = IMap.find_unsafe exports_tmap json_cx.cx.property_maps in
       json_of_tmap json_cx tmap);

      "cjsExport",
      match cjs_export with Some(t) -> _json_of_t json_cx t | None -> JNull;
    ]

  | SummarizeT (_, t) -> [
      "type", _json_of_t json_cx t
    ]

  | CallT (_, funtype) -> [
      "funType", json_of_funtype json_cx funtype
    ]

  | MethodT (_, name, funtype) -> [
      "name", JString name;
      "funType", json_of_funtype json_cx funtype
    ]

  | SetPropT (_, name, t)
  | GetPropT (_, name, t) -> [
      "propName", json_of_proptype json_cx name;
      "propType", _json_of_t json_cx t
    ]

  | SetElemT (_, indext, elemt)
  | GetElemT (_, indext, elemt) -> [
      "indexType", _json_of_t json_cx indext;
      "elemType", _json_of_t json_cx elemt
    ]

  | ConstructorT (_, tparams, t) -> [
      "typeParams", JList (List.map (_json_of_t json_cx) tparams);
      "type", _json_of_t json_cx t
    ]

  | SuperT (_, instance) -> [
      "instance", json_of_insttype json_cx instance
    ]

  | ExtendsT (_, t1, t2) -> [
      "type1", _json_of_t json_cx t1;
      "type2", _json_of_t json_cx t2
    ]

  | AdderT (_, l, r) -> [
      "leftType", _json_of_t json_cx l;
      "rightType", _json_of_t json_cx r
    ]

  | ComparatorT (_, t) -> [
      "type", _json_of_t json_cx t
    ]

  | PredicateT (p, t) -> [
      "pred", json_of_pred json_cx p;
      "type", _json_of_t json_cx t
    ]

  | EqT (_, t) -> [
      "type", _json_of_t json_cx t
    ]

  | AndT (_, right, res)
  | OrT (_, right, res) -> [
      "rightType", _json_of_t json_cx right;
      "resultType", _json_of_t json_cx res
    ]

  | NotT (_, t) -> [
      "type", _json_of_t json_cx t
    ]

  | SpecializeT (_, cache, targs, tvar) -> [
      "cache", JBool cache;
      "types", JList (List.map (_json_of_t json_cx) targs);
      "tvar", _json_of_t json_cx tvar
    ]

  | LookupT (_, rstrict, _, name, t) ->
    (match rstrict with
      | None -> []
      | Some r -> ["strictReason", json_of_reason r]
    ) @ [
      "name", JString name;
      "type", _json_of_t json_cx t
    ]

  | ObjAssignT (_, assignee, tvar, prop_names, flag) -> [
      "assigneeType", _json_of_t json_cx assignee;
      "resultType", _json_of_t json_cx tvar;
      "propNames", JList (List.map (fun s -> JString s) prop_names);
      "flag", JBool flag
    ]

  | ObjFreezeT (_, t) -> [
      "type", _json_of_t json_cx t
    ]

  | ObjRestT (_, excludes, tvar) -> [
      "excludedProps", JList (List.map (fun s -> JString s) excludes);
      "resultType", _json_of_t json_cx tvar;
    ]

  | ObjSealT (_, t) -> [
      "type", _json_of_t json_cx t
    ]

  | ObjTestT (_, default, res) -> [
      "defaultType", _json_of_t json_cx default;
      "resultType", _json_of_t json_cx res
    ]

  | UnifyT (t1, t2) -> [
      "type1", _json_of_t json_cx t1;
      "type2", _json_of_t json_cx t2
    ]

  | ConcretizeT (l, todo_list, done_list, u) -> [
      "inType", _json_of_t json_cx l;
      "todoTypes", JList (List.map (_json_of_t json_cx) todo_list);
      "doneTypes", JList (List.map (_json_of_t json_cx) done_list);
      "absType", _json_of_t json_cx u
    ]

  | ConcreteT t
  | GetKeysT (_, t) -> [
      "type", _json_of_t json_cx t
    ]

  | HasKeyT (_, key) -> [
      "key", JString key
    ]

  | ElemT (_, base, elem) -> [
      "baseType", _json_of_t json_cx base;
      "elemType", _json_of_t json_cx elem
    ]

  | CJSRequireT (_, export) -> [
      "export",
      _json_of_t json_cx export
    ]
  | ImportModuleNsT (_, t)
  | ImportTypeT (_, t)
  | ImportTypeofT (_, t)
    -> ["type", _json_of_t json_cx t]

  | CJSExtractNamedExportsT (_, module_t, t_out) -> [
      "module", _json_of_t json_cx module_t;
      "t_out", _json_of_t json_cx t_out;
    ]
  | SetNamedExportsT (_, tmap, t_out) -> [
      "tmap", json_of_tmap json_cx tmap;
      "t_out", _json_of_t json_cx t_out;
    ]
  | SetCJSExportT (_, t, t_out) -> [
      "cjsExportType", _json_of_t json_cx t;
      "t_out", _json_of_t json_cx t_out;
    ]
))

and json_of_polarity json_cx = check_depth json_of_polarity_impl json_cx
and json_of_polarity_impl json_cx polarity =
  Json.JString (match polarity with
  | Negative -> "Negative"
  | Neutral -> "Neutral"
  | Positive -> "Positive"
)

and json_of_typeparam json_cx = check_depth json_of_typeparam_impl json_cx
and json_of_typeparam_impl json_cx tparam = Json.(
  JAssoc [
    "reason", json_of_reason tparam.reason;
    "name", JString tparam.name;
    "bound", _json_of_t json_cx tparam.bound;
    "polarity", json_of_polarity json_cx tparam.polarity;
  ]
)

and json_of_objtype json_cx = check_depth json_of_objtype_impl json_cx
and json_of_objtype_impl json_cx objtype = Json.(
  JAssoc ([
    "flags", json_of_flags json_cx objtype.flags;
  ] @ (match objtype.dict_t with
    | None -> []
    | Some d -> ["dictType", json_of_dicttype json_cx d]
  ) @ [
    "propTypes",
      (let tmap = IMap.find_unsafe objtype.props_tmap json_cx.cx.property_maps in
      json_of_tmap json_cx tmap);
    "prototype", _json_of_t json_cx objtype.proto_t
  ])
)

and json_of_dicttype json_cx = check_depth json_of_dicttype_impl json_cx
and json_of_dicttype_impl json_cx dicttype = Json.(
  JAssoc (
    (match dicttype.dict_name with
    | None -> []
    | Some name -> ["name", JString name]
  ) @ [
    "keyType", _json_of_t json_cx dicttype.key;
    "valueType", _json_of_t json_cx dicttype.value
  ])
)

and json_of_flags json_cx = check_depth json_of_flags_impl json_cx
and json_of_flags_impl json_cx flags = Json.(
  JAssoc [
    "frozen", JBool flags.frozen;
    "sealed", JBool (match flags.sealed with
      | Sealed -> true
      | UnsealedInFile _ -> false);
    "exact", JBool flags.exact;
  ]
)

and json_of_funtype json_cx = check_depth json_of_funtype_impl json_cx
and json_of_funtype_impl json_cx funtype = Json.(
  JAssoc ([
    "thisType", _json_of_t json_cx funtype.this_t;
    "paramTypes", JList (List.map (_json_of_t json_cx) funtype.params_tlist)
  ] @ (match funtype.params_names with
    | None -> []
    | Some names -> ["paramNames", JList (List.map (fun s -> JString s) names)]
  ) @ [
    "returnType", _json_of_t json_cx funtype.return_t;
    "closureTypeIndex", JInt funtype.closure_t
  ])
)

and json_of_insttype json_cx = check_depth json_of_insttype_impl json_cx
and json_of_insttype_impl json_cx insttype = Json.(
  JAssoc [
    "classId", JInt insttype.class_id;
    "typeArgs", json_of_tmap json_cx insttype.type_args;
    "argPolarities", json_of_polarity_map json_cx insttype.arg_polarities;
    "fieldTypes",
      (let tmap = IMap.find_unsafe insttype.fields_tmap json_cx.cx.property_maps in
       json_of_tmap json_cx tmap);
    "methodTypes",
      (let tmap = IMap.find_unsafe insttype.methods_tmap json_cx.cx.property_maps in
       json_of_tmap json_cx tmap);
    "mixins", JBool insttype.mixins;
    "structural", JBool insttype.structural;
  ]
)

and json_of_polarity_map json_cx = check_depth json_of_polarity_map_impl json_cx
and json_of_polarity_map_impl json_cx pmap = Json.(
  let lst = SMap.fold (fun name pol acc ->
    JAssoc ["name", JString name; "polarity", json_of_polarity json_cx pol] :: acc
  ) pmap [] in
  JList (List.rev lst)
)

and json_of_proptype json_cx = check_depth json_of_proptype_impl json_cx
and json_of_proptype_impl json_cx (reason, literal) = Json.(
  JAssoc [
    "reason", json_of_reason reason;
    "literal", JString literal;
  ]
)

and json_of_tmap json_cx = check_depth json_of_tmap_impl json_cx
and json_of_tmap_impl json_cx bindings = Json.(
  let lst = SMap.fold (fun name t acc ->
    json_of_type_binding json_cx (name, t) :: acc
  ) bindings [] in
  JList (List.rev lst)
)

and json_of_type_binding json_cx = check_depth json_of_type_binding_impl json_cx
and json_of_type_binding_impl json_cx (name, t) = Json.(
  JAssoc ["name", JString name; "type", _json_of_t json_cx t]
)

and json_of_pred json_cx = check_depth json_of_pred_impl json_cx
and json_of_pred_impl json_cx p = Json.(
  JAssoc ([
    "kind", JString (string_of_pred_ctor p)
  ] @
  match p with
  | AndP (l, r)
  | OrP (l, r) -> [
      "left", json_of_pred json_cx l;
      "right", json_of_pred json_cx r
    ]
  | NotP p -> ["pred", json_of_pred json_cx p]
  | LeftP (b, t)
  | RightP (b, t) -> [
      "binaryTest", json_of_binary_test json_cx b;
      "type", _json_of_t json_cx t
    ]
  | ExistsP -> []
  | IsP s -> ["typeName", JString s]
))

and json_of_binary_test json_cx = check_depth json_of_binary_test_impl json_cx
and json_of_binary_test_impl json_cx b = Json.(
  JAssoc ([
    "kind", JString (string_of_binary_test_ctor b)
  ] @
  match b with
  | Instanceof -> []
  | SentinelProp s -> ["key", JString s]
))

and json_of_node json_cx = check_depth json_of_node_impl json_cx
and json_of_node_impl json_cx id = Json.(
  JAssoc (
    let json_cx = { json_cx with stack = ISet.add id json_cx.stack } in
    match IMap.find_unsafe id json_cx.cx.graph with
    | Goto id ->
      ["kind", JString "Goto"]
      @ ["id", JInt id]
    | Root root ->
      ["kind", JString "Root"]
      @ ["root", json_of_root json_cx root]
  )
)

and json_of_root json_cx = check_depth json_of_root_impl json_cx
and json_of_root_impl json_cx root = Json.(
  JAssoc ([
    "rank", JInt root.rank;
    "constraints", json_of_constraints json_cx root.constraints
  ])
)

and json_of_constraints json_cx = check_depth json_of_constraints_impl json_cx
and json_of_constraints_impl json_cx constraints = Json.(
  JAssoc (
    match constraints with
    | Resolved t ->
      ["kind", JString "Resolved"]
      @ ["type", _json_of_t json_cx t]
    | Unresolved bounds ->
      ["kind", JString "Unresolved"]
      @ ["bounds", json_of_bounds json_cx bounds]
  )
)

and json_of_bounds json_cx = check_depth json_of_bounds_impl json_cx
and json_of_bounds_impl json_cx bounds = Json.(
  match bounds with
  | { lower; upper; lowertvars; uppertvars; } -> JAssoc ([
      "lower", json_of_tkeys json_cx lower;
      "upper", json_of_tkeys json_cx upper;
      "lowertvars", json_of_tvarkeys json_cx lowertvars;
      "uppertvars", json_of_tvarkeys json_cx uppertvars;
    ])
)

and json_of_tkeys json_cx = check_depth json_of_tkeys_impl json_cx
and json_of_tkeys_impl json_cx tmap = Json.(
  JList (TypeMap.fold (fun t _ acc -> _json_of_t json_cx t :: acc) tmap [])
)

and json_of_tvarkeys json_cx = check_depth json_of_tvarkeys_impl json_cx
and json_of_tvarkeys_impl json_cx imap = Json.(
  JList (IMap.fold (fun i _ acc -> JInt i :: acc) imap [])
)

let json_of_t ?(depth=1000) cx t =
  let json_cx = { cx; depth; stack = ISet.empty; } in
  _json_of_t json_cx t

let jstr_of_t ?(depth=1000) cx t =
  Json.json_to_multiline (json_of_t ~depth cx t)

let json_of_graph ?(depth=1000) cx = Json.(
  let entries = IMap.fold (fun id _ entries ->
    let json_cx = { cx; depth; stack = ISet.empty; } in
    (spf "%d" id, json_of_node json_cx id) :: entries
  ) cx.graph [] in
  JAssoc (List.rev entries)
)

let jstr_of_graph ?(depth=1000) cx =
  Json.json_to_multiline (json_of_graph ~depth cx)

(****************** end json ******************)

(* debug printer *)
let rec dump_t cx t =
  dump_t_ ISet.empty cx t

and dump_t_ =
  (* we'll want to add more here *)
  let override stack cx t = match t with
    | OpenT (r, id) -> Some (dump_tvar stack cx r id)
    | NumT (r, lit) -> Some (match lit with
        | Literal (_, raw) -> spf "NumT(%s)" raw
        | Truthy -> spf "NumT(truthy)"
        | Falsy -> spf "NumT(0)"
        | AnyLiteral -> "NumT")
    | StrT (r, c) -> Some (match c with
        | Literal s -> spf "StrT(%S)" s
        | Truthy -> spf "StrT(truthy)"
        | Falsy -> spf "StrT(falsy)"
        | AnyLiteral -> "StrT")
    | BoolT (r, c) -> Some (match c with
        | Some b -> spf "BoolT(%B)" b
        | None -> "BoolT")
    | UndefT _
    | MixedT _
    | AnyT _
    | NullT _ -> Some (string_of_ctor t)
    | SetPropT (_, (_, n), t) ->
        Some (spf "SetPropT(%s: %s)" n (dump_t_ stack cx t))
    | GetPropT (_, (_, n), t) ->
        Some (spf "GetPropT(%s: %s)" n (dump_t_ stack cx t))
    | LookupT (_, _, ts, n, t) ->
        Some (spf "LookupT(%s: %s)" n (dump_t_ stack cx t))
    | PredicateT (p, t) -> Some (spf "PredicateT(%s | %s)"
        (string_of_predicate p) (dump_t_ stack cx t))
    | _ -> None
  in
  fun stack cx t ->
    type_printer (override stack) string_of_ctor EnclosureNone cx t

(* type variable dumper. abbreviates a few simple cases for readability.
   note: if we turn the tvar record into a datatype, these will give a
   sense of some of the obvious data constructors *)
and dump_tvar stack cx r id =
  let sbounds = if ISet.mem id stack then "(...)" else (
    let stack = ISet.add id stack in
    match IMap.find_unsafe id cx.graph with
    | Goto id -> spf "Goto TYPE_%d" id
    | Root { rank; constraints = Resolved t } ->
        spf "Root (rank = %d, resolved = %s)"
          rank (dump_t_ stack cx t)
    | Root { rank; constraints = Unresolved bounds } ->
        spf "Root (rank = %d, unresolved = %s)"
          rank (dump_bounds stack cx id bounds)
  ) in
  (spf "TYPE_%d: " id) ^ sbounds

and dump_bounds stack cx id bounds = match bounds with
  | { lower; upper; lowertvars; uppertvars; }
      when lower = TypeMap.empty && upper = TypeMap.empty
      && IMap.cardinal lowertvars = 1 && IMap.cardinal uppertvars = 1 ->
      (* no inflows or outflows *)
      "(free)"
  | { lower; upper; lowertvars; uppertvars; }
      when upper = TypeMap.empty
      && IMap.cardinal lowertvars = 1 && IMap.cardinal uppertvars = 1 ->
      (* only concrete inflows *)
      spf "L %s" (dump_tkeys stack cx lower)
  | { lower; upper; lowertvars; uppertvars; }
      when lower = TypeMap.empty && upper = TypeMap.empty
      && IMap.cardinal uppertvars = 1 ->
      (* only tvar inflows *)
      spf "LV %s" (dump_tvarkeys cx id lowertvars)
  | { lower; upper; lowertvars; uppertvars; }
      when lower = TypeMap.empty
      && IMap.cardinal lowertvars = 1 && IMap.cardinal uppertvars = 1 ->
      (* only concrete outflows *)
      spf "U %s" (dump_tkeys stack cx upper)
  | { lower; upper; lowertvars; uppertvars; }
      when lower = TypeMap.empty && upper = TypeMap.empty
      && IMap.cardinal lowertvars = 1 ->
      (* only tvar outflows *)
      spf "UV %s" (dump_tvarkeys cx id uppertvars)
  | { lower; upper; lowertvars; uppertvars; }
      when IMap.cardinal lowertvars = 1 && IMap.cardinal uppertvars = 1 ->
      (* only concrete inflows/outflows *)
      let l = dump_tkeys stack cx lower in
      let u = dump_tkeys stack cx upper in
      if l = u then "= " ^ l
      else "L " ^ l ^ " U " ^ u
  | { lower; upper; lowertvars; uppertvars; } ->
    let slower = if lower = TypeMap.empty then "" else
      spf " lower = %s;" (dump_tkeys stack cx lower) in
    let supper = if upper = TypeMap.empty then "" else
      spf " upper = %s;" (dump_tkeys stack cx upper) in
    let sltvars = if IMap.cardinal lowertvars <= 1 then "" else
      spf " lowertvars = %s;" (dump_tvarkeys cx id lowertvars) in
    let sutvars = if IMap.cardinal uppertvars <= 1 then "" else
      spf " uppertvars = %s;" (dump_tvarkeys cx id uppertvars) in
    "{" ^ slower ^ supper ^ sltvars ^ sutvars ^ " }"

(* dump the keys of a type map as a list *)
and dump_tkeys stack cx tmap =
  "[" ^ (
    String.concat "," (
      List.rev (
        TypeMap.fold (
          fun t _ acc -> dump_t_ stack cx t :: acc
        ) tmap []
      )
    )
  ) ^ "]"

(* dump the keys of a tvar map as a list *)
and dump_tvarkeys cx self imap =
  "[" ^ (
    String.concat "," (
      List.rev (
        IMap.fold (
          fun id _ acc ->
            if id = self then acc else spf "TYPE_%d" id :: acc
        ) imap []
      )
    )
  ) ^ "]"

let rec is_printed_type_parsable_impl weak cx enclosure = function
  (* Base cases *)
  | BoundT _
  | NumT _
  | StrT _
  | BoolT _
  | AnyT _
    ->
      true

  | VoidT _
    when (enclosure == EnclosureRet)
    ->
      true

  | AnnotT (_, t) ->
      is_printed_type_parsable_impl weak cx enclosure t

  (* Composed types *)
  | MaybeT t
    ->
      is_printed_type_parsable_impl weak cx EnclosureMaybe t

  | ArrT (_, t, ts)
    ->
      (*(match ts with
      | [] -> *)is_printed_type_parsable_impl weak cx EnclosureNone t
      (*| _ ->
          is_printed_type_list_parsable weak cx EnclosureNone t*)

  | RestT t
  | OptionalT t
    when (enclosure == EnclosureParam)
    ->
      is_printed_type_parsable_impl weak cx EnclosureNone t

  | FunT (_, _, _, { params_tlist; return_t; _ })
    ->
      (is_printed_type_parsable_impl weak cx EnclosureRet return_t) &&
      (is_printed_type_list_parsable weak cx EnclosureParam params_tlist)

  | ObjT (_, { props_tmap; dict_t; _ })
    ->
      let is_printable =
        match dict_t with
        | Some { key; value; _ } ->
            (is_printed_type_parsable_impl weak cx EnclosureNone key) &&
            (is_printed_type_parsable_impl weak cx EnclosureNone value)
        | None -> true
      in
      let prop_map = IMap.find_unsafe props_tmap cx.property_maps in
      SMap.fold (fun name t acc ->
          acc && (
            (* We don't print internal properties, thus we do not care whether
               their type is printable or not *)
            (Reason_js.is_internal_name name) ||
            (is_printed_type_parsable_impl weak cx EnclosureNone t)
          )
        ) prop_map is_printable

  | InstanceT _
    ->
      true

  | IntersectionT (_, ts)
    ->
      is_printed_type_list_parsable weak cx EnclosureIntersect ts

  | UnionT (_, ts)
    ->
      is_printed_type_list_parsable weak cx EnclosureUnion ts

  | PolyT (_, t)
    ->
      is_printed_type_parsable_impl weak cx EnclosureNone t

  | AnyObjT _ -> true
  | AnyFunT _ -> true

  (* weak mode *)

  (* these are types which are not really parsable, but they make sense to a
     human user in cases of autocompletion *)
  | OptionalT t
  | RestT t
  | TypeT (_, t)
  | LowerBoundT t
  | UpperBoundT t
  | ClassT t
    when weak
    ->
      is_printed_type_parsable_impl weak cx EnclosureNone t

  | VoidT _
    when weak
    ->
      true

  (* This gives really ugly output, but would need to figure out a better way
     to print these types otherwise, maybe substitute on printing? *)
  | TypeAppT (t, ts)
    when weak
    ->
      (is_printed_type_parsable_impl weak cx EnclosureAppT t) &&
      (is_printed_type_list_parsable weak cx EnclosureNone ts)

  | _
    ->
      false

and is_printed_type_list_parsable weak cx enclosure ts =
  List.fold_left (fun acc t ->
      acc && (is_printed_type_parsable_impl weak cx enclosure t)
    ) true ts

let is_printed_type_parsable ?(weak=false) cx t =
  is_printed_type_parsable_impl weak cx EnclosureNone t

let is_printed_param_type_parsable ?(weak=false) cx t =
  is_printed_type_parsable_impl weak cx EnclosureParam t

(*****************************************************************)

(* scopes and types *)

let string_of_loc_opt = function
| Some loc -> string_of_loc loc
| None -> "(none)"

let string_of_entry = Scope.(

  let string_of_value cx {
    Entry.kind; value_state; value_loc; specific; general
  } =
    Utils.spf "{ kind: %s; value_state: %s; value_loc: %s; \
      specific: %s; general: %s }"
      (Entry.string_of_value_kind kind)
      (Entry.string_of_state value_state)
      (string_of_loc_opt value_loc)
      (dump_t cx specific)
      (dump_t cx general)
  in

  let string_of_type cx { Entry.type_state; type_loc; _type } =
    Utils.spf "{ type_state: %s; type_loc: %s; _type: %s }"
      (Entry.string_of_state type_state)
      (string_of_loc_opt type_loc)
      (dump_t cx _type)
  in

  fun cx -> Entry.(function
  | Value r -> spf "Value %s" (string_of_value cx r)
  | Type r -> spf "Type %s" (string_of_type cx r)
  )
)

let string_of_scope = Scope.(

  let string_of_entries cx entries =
    SMap.fold (fun name entry acc ->
      (Utils.spf "%s: %s" name (string_of_entry cx entry))
        :: acc
    ) entries []
    |> String.concat ";\n  "
  in

  let string_of_refi cx { refi_loc; refined; original } =
    Utils.spf "{ refi_loc: %s; refined: %s; original: %s }"
      (string_of_loc_opt refi_loc)
      (dump_t cx refined)
      (dump_t cx original)
  in

  let string_of_refis cx refis =
    KeyMap.fold (fun key refi acc ->
      (Utils.spf "%s: %s" (Key.string_of_key key) (string_of_refi cx refi))
        :: acc
    ) refis []
    |> String.concat ";\n  "
  in

  let string_of_function_kind = function
  | Ordinary -> "Ordinary"
  | Async -> "Async"
  | Generator -> "Generator"
  in

  let string_of_scope_kind = function
  | VarScope kind -> spf "VarScope %s" (string_of_function_kind kind)
  | LexScope -> "LexScope"
  in

  fun cx scope ->
    Utils.spf "{ kind: %s;\nentries:\n%s\nrefis:\n%s\n}"
      (string_of_scope_kind scope.kind)
      (string_of_entries cx scope.entries)
      (string_of_refis cx scope.refis)
)

(*****************************************************************)

(* traces and types *)

let level_spaces level indent = indent * level

let spaces n = String.make n ' '

let fill n tab =
  let rec loop n =
    if n <= 0 then ""
    else if n < tab then "." ^ (spaces (n - 1))
    else "." ^ (spaces (tab - 1)) ^ (loop (n - tab))
  in loop n

let prep_path r =
  if not (Modes_js.modes.strip_root) then r
  else
    let path = FlowConfig.((get_unsafe ()).root) in
    Reason_js.strip_root path r

(* string length of printed position, as it would
   appear in an error *)
let pos_len r =
  let r = prep_path r in
  let loc = loc_of_reason r in
  let fmt = Errors_js.(format_reason_color (BlameM (loc, ""))) in
  let str = String.concat "" (List.map snd fmt) in
  String.length str

(* scan a trace tree, return maximum position length
   of reasons at or above the given depth limit, and
   min of that limit and actual max depth *)
let max_pos_len_and_depth limit trace =
  let rec f (len, depth) (lower, upper, parent, _) =
    let len = max len (pos_len (reason_of_t lower)) in
    let len = max len (pos_len (reason_of_t upper)) in
    if depth > limit then len, depth
    else Trace.(
      match parent with
      | Parent [] -> len, depth
      | Parent trace -> List.fold_left f (len, depth + 1) trace
    )
  in List.fold_left f (0, 0) trace

(* reformat a reason's description with
   - the given left margin
   - the given prefix and suffix: if either is nonempty,
     "desc" becomes "prefix[desc]suffix"
  *)
let pretty_r margin r prefix suffix =
  let len = pos_len r in
  let ind = if margin > len then spaces (margin - len) else "" in
  if prefix = "" && suffix = ""
  then prefix_reason ind r
  else wrap_reason (ind ^ (spf "%s[" prefix)) (spf "]%s" suffix) r

(* helper: we want the tvar id as well *)
(* NOTE: uncalled for now, because ids are nondetermistic
   due to parallelism, which messes up test diffs. Should
   add a config, but for now must uncomment impl to use *)
let reason_of_t_add_id = reason_of_t
(* function
| OpenT (r, id) -> prefix_reason (spf "%d: " id) r
| t -> reason_of_t t *)

(* prettyprint a trace. what we print:

   - a list of paths, numbered 1..n, root first.

   - for each path, its list of steps.
     usually a step is 2 main lines, one each for lower and upper.
     but we elide the former if its a tvar that was also the  prior
     step's upper.
     if the step was derived from another path, we append a note
     to that effect.
 *)
let reasons_of_trace ?(level=0) trace =
  let max_pos_len, max_depth = max_pos_len_and_depth level trace in
  let level = min level max_depth in

  let tmap, imap = index_trace level trace in

  let print_step steps i (lower, upper, Trace.Parent parent, _) =
    (* omit lower if it's a pipelined tvar *)
    (if i > 0 &&
      lower = (match List.nth steps (i - 1) with (_, upper, _, _) -> upper)
    then []
    else [pretty_r max_pos_len (reason_of_t_add_id lower)
      (spf "%s " (string_of_ctor lower)) ""]
    )
    @
    [pretty_r max_pos_len (reason_of_t_add_id upper)
      (spf "~> %s " (string_of_ctor upper))
      (if parent = []
        then ""
        else match TraceMap.get parent tmap with
        | Some i -> spf " (from path %d)" (i + 1)
        | None -> " (from [not shown])"
      )
    ]
  in

  let print_path i steps =
    (reason_of_string (spf "* path %d:" (i + 1))) ::
    List.concat (List.mapi (print_step steps) steps)
  in

  List.concat (List.rev (IMap.fold (
    fun i flow acc -> (print_path i flow) :: acc
  ) imap []))

(********* type visitor *********)

(* We walk types in a lot of places for all kinds of things, but often most of
   the code is boilerplate. The following visitor class for types aims to
   reduce that boilerplate. It is designed as a fold on the structure of types,
   parameterized by an accumulator.

   WARNING: This is only a partial implementation, sufficient for current
   purposes but intended to be completed in a later diff.
*)
class ['a] type_visitor = object(self)
  method type_ cx (acc: 'a) = function
  | OpenT (_, id) -> self#id_ cx acc id

  | NumT _
  | StrT _
  | BoolT _
  | UndefT _
  | MixedT _
  | AnyT _
  | NullT _
  | VoidT _ -> acc

  | FunT (_, static, prototype, funtype) ->
    let acc = self#type_ cx acc static in
    let acc = self#type_ cx acc prototype in
    let acc = self#fun_type cx acc funtype in
    acc

  | ObjT (_, { dict_t; props_tmap; proto_t; _ }) ->
    let acc = self#opt (self#dict_ cx) acc dict_t in
    let acc = self#props cx acc props_tmap in
    let acc = self#type_ cx acc proto_t in
    acc

  | ArrT (_, t, ts) ->
    let acc = self#type_ cx acc t in
    let acc = self#list (self#type_ cx) acc ts in
    acc

  | ClassT t -> self#type_ cx acc t

  | InstanceT (_, static, super, insttype) ->
    let acc = self#type_ cx acc static in
    let acc = self#type_ cx acc super in
    let acc = self#inst_type cx acc insttype in
    acc

  | OptionalT t -> self#type_ cx acc t

  | RestT t -> self#type_ cx acc t

  | PolyT (typeparams, t) ->
    let acc = self#list (self#type_param cx) acc typeparams in
    let acc = self#type_ cx acc t in
    acc

  | TypeAppT (t, ts) ->
    let acc = self#type_ cx acc t in
    let acc = self#list (self#type_ cx) acc ts in
    acc

  | BoundT typeparam -> self#type_param cx acc typeparam

  | ExistsT _ -> acc

  | MaybeT t -> self#type_ cx acc t

  | IntersectionT (_, ts)
  | UnionT (_, ts) -> self#list (self#type_ cx) acc ts

  | UpperBoundT t
  | LowerBoundT t -> self#type_ cx acc t

  | AnyObjT _
  | AnyFunT _ -> acc

  | ShapeT t -> self#type_ cx acc t

  | DiffT (t1, t2) ->
    let acc = self#type_ cx acc t1 in
    let acc = self#type_ cx acc t2 in
    acc

  | KeysT (_, t) -> self#type_ cx acc t

  | SingletonStrT _
  | SingletonNumT _
  | SingletonBoolT _ -> acc

  | TypeT (_, t) -> self#type_ cx acc t

  | AnnotT (t1, t2) ->
    let acc = self#type_ cx acc t1 in
    let acc = self#type_ cx acc t2 in
    acc

  | BecomeT (_, t) -> self#type_ cx acc t

  | SpeculativeMatchFailureT (_, t1, t2) ->
    let acc = self#type_ cx acc t1 in
    let acc = self#type_ cx acc t2 in
    acc

  | ModuleT (_, exporttypes) ->
    self#export_types cx acc exporttypes

  (* Currently not walking use types. This will change in an upcoming diff. *)
  | SummarizeT (_, _)
  | CallT (_, _)
  | MethodT (_, _, _)
  | SetPropT (_, _, _)
  | GetPropT (_, _, _)
  | SetElemT (_, _, _)
  | GetElemT (_, _, _)
  | ConstructorT (_, _, _)
  | SuperT (_, _)
  | ExtendsT (_, _, _)
  | AdderT (_, _, _)
  | ComparatorT (_, _)
  | PredicateT (_, _)
  | EqT (_, _)
  | AndT (_, _, _)
  | OrT (_, _, _)
  | NotT (_, _)
  | SpecializeT (_, _, _, _)
  | LookupT (_, _, _, _, _)
  | ObjAssignT (_, _, _, _, _)
  | ObjFreezeT (_, _)
  | ObjRestT (_, _, _)
  | ObjSealT (_, _)
  | ObjTestT (_, _, _)
  | UnifyT (_, _)
  | ConcretizeT (_, _, _, _)
  | ConcreteT _
  | GetKeysT (_, _)
  | HasKeyT (_, _)
  | ElemT (_, _, _)
  | CJSRequireT (_, _)
  | ImportModuleNsT (_, _)
  | ImportTypeT (_, _)
  | ImportTypeofT (_, _)
  | CJSExtractNamedExportsT (_, _, _)
  | SetCJSExportT (_, _, _)
  | SetNamedExportsT (_, _, _)
    -> self#__TODO__ cx acc

  (* The default behavior here could be fleshed out a bit, to look up the graph,
     handle Resolved and Unresolved cases, etc. *)
  method id_ cx acc id = acc

  method private dict_ cx acc { key; value; _ } =
    let acc = self#type_ cx acc key in
    let acc = self#type_ cx acc value in
    acc

  method props cx acc id =
    self#smap (self#type_ cx) acc (IMap.find_unsafe id cx.property_maps)

  method private type_param cx acc { bound; _ } =
    self#type_ cx acc bound

  method fun_type cx acc { this_t; params_tlist; return_t; _ } =
    let acc = self#type_ cx acc this_t in
    let acc = self#list (self#type_ cx) acc params_tlist in
    let acc = self#type_ cx acc return_t in
    acc

  method private inst_type cx acc { type_args; fields_tmap; methods_tmap; _ } =
    let acc = self#smap (self#type_ cx) acc type_args in
    let acc = self#props cx acc fields_tmap in
    let acc = self#props cx acc methods_tmap in
    acc

  method private export_types cx acc { exports_tmap; cjs_export } =
    let acc = self#props cx acc exports_tmap in
    let acc = self#opt (self#type_ cx) acc cjs_export in
    acc

  method private __TODO__ cx acc = acc

  method private list: 't. ('a -> 't -> 'a) -> 'a -> 't list -> 'a =
    List.fold_left

  method private opt: 't. ('a -> 't -> 'a) -> 'a -> 't option -> 'a =
    fun f acc -> function
    | None -> acc
    | Some x -> f acc x

  method private smap: 't. ('a -> 't -> 'a) -> 'a -> 't SMap.t -> 'a =
    fun f acc map ->
      SMap.fold (fun _ t acc -> f acc t) map acc
end
