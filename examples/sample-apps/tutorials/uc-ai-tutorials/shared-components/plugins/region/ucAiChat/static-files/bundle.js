var UcApexChat = (function() {
	//#region node_modules/svelte/src/internal/disclose-version.js
	if (typeof window !== "undefined") ((window.__svelte ??= {}).v ??= /* @__PURE__ */ new Set()).add("5");
	//#endregion
	//#region node_modules/svelte/src/constants.js
	var HYDRATION_ERROR = {};
	var UNINITIALIZED = Symbol();
	var NAMESPACE_HTML = "http://www.w3.org/1999/xhtml";
	var NAMESPACE_SVG = "http://www.w3.org/2000/svg";
	var NAMESPACE_MATHML = "http://www.w3.org/1998/Math/MathML";
	//#endregion
	//#region node_modules/svelte/src/internal/shared/utils.js
	var is_array = Array.isArray;
	var index_of = Array.prototype.indexOf;
	var includes = Array.prototype.includes;
	var array_from = Array.from;
	var object_keys = Object.keys;
	var define_property = Object.defineProperty;
	var get_descriptor = Object.getOwnPropertyDescriptor;
	var get_descriptors = Object.getOwnPropertyDescriptors;
	var object_prototype = Object.prototype;
	var array_prototype = Array.prototype;
	var get_prototype_of = Object.getPrototypeOf;
	var is_extensible = Object.isExtensible;
	var noop = () => {};
	/** @param {Array<() => void>} arr */
	function run_all(arr) {
		for (var i = 0; i < arr.length; i++) arr[i]();
	}
	/**
	* TODO replace with Promise.withResolvers once supported widely enough
	* @template [T=void]
	*/
	function deferred() {
		/** @type {(value: T) => void} */
		var resolve;
		/** @type {(reason: any) => void} */
		var reject;
		return {
			promise: new Promise((res, rej) => {
				resolve = res;
				reject = rej;
			}),
			resolve,
			reject
		};
	}
	var CLEAN = 1024;
	var DIRTY = 2048;
	var MAYBE_DIRTY = 4096;
	var INERT = 8192;
	var DESTROYED = 16384;
	/** Set once a reaction has run for the first time */
	var REACTION_RAN = 32768;
	/** Effect is in the process of getting destroyed. Can be observed in child teardown functions */
	var DESTROYING = 1 << 25;
	/**
	* 'Transparent' effects do not create a transition boundary.
	* This is on a block effect 99% of the time but may also be on a branch effect if its parent block effect was pruned
	*/
	var EFFECT_TRANSPARENT = 65536;
	var EFFECT_PRESERVED = 1 << 19;
	var USER_EFFECT = 1 << 20;
	var EFFECT_OFFSCREEN = 1 << 25;
	/**
	* Tells that we marked this derived and its reactions as visited during the "mark as (maybe) dirty"-phase.
	* Will be lifted during execution of the derived and during checking its dirty state (both are necessary
	* because a derived might be checked but not executed).
	*/
	var WAS_MARKED = 65536;
	var REACTION_IS_UPDATING = 1 << 21;
	var ASYNC = 1 << 22;
	var ERROR_VALUE = 1 << 23;
	var STATE_SYMBOL = Symbol("$state");
	var LEGACY_PROPS = Symbol("legacy props");
	var LOADING_ATTR_SYMBOL = Symbol("");
	/** allow users to ignore aborted signal errors if `reason.name === 'StaleReactionError` */
	var STALE_REACTION = new class StaleReactionError extends Error {
		name = "StaleReactionError";
		message = "The reaction that called `getAbortSignal()` was re-run or destroyed";
	}();
	var IS_XHTML = !!globalThis.document?.contentType && /* @__PURE__ */ globalThis.document.contentType.includes("xml");
	/**
	* `%name%(...)` can only be used during component initialisation
	* @param {string} name
	* @returns {never}
	*/
	function lifecycle_outside_component(name) {
		throw new Error(`https://svelte.dev/e/lifecycle_outside_component`);
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/errors.js
	/**
	* Cannot create a `$derived(...)` with an `await` expression outside of an effect tree
	* @returns {never}
	*/
	function async_derived_orphan() {
		throw new Error(`https://svelte.dev/e/async_derived_orphan`);
	}
	/**
	* Keyed each block has duplicate key `%value%` at indexes %a% and %b%
	* @param {string} a
	* @param {string} b
	* @param {string | undefined | null} [value]
	* @returns {never}
	*/
	function each_key_duplicate(a, b, value) {
		throw new Error(`https://svelte.dev/e/each_key_duplicate`);
	}
	/**
	* `%rune%` cannot be used inside an effect cleanup function
	* @param {string} rune
	* @returns {never}
	*/
	function effect_in_teardown(rune) {
		throw new Error(`https://svelte.dev/e/effect_in_teardown`);
	}
	/**
	* Effect cannot be created inside a `$derived` value that was not itself created inside an effect
	* @returns {never}
	*/
	function effect_in_unowned_derived() {
		throw new Error(`https://svelte.dev/e/effect_in_unowned_derived`);
	}
	/**
	* `%rune%` can only be used inside an effect (e.g. during component initialisation)
	* @param {string} rune
	* @returns {never}
	*/
	function effect_orphan(rune) {
		throw new Error(`https://svelte.dev/e/effect_orphan`);
	}
	/**
	* Maximum update depth exceeded. This typically indicates that an effect reads and writes the same piece of state
	* @returns {never}
	*/
	function effect_update_depth_exceeded() {
		throw new Error(`https://svelte.dev/e/effect_update_depth_exceeded`);
	}
	/**
	* Failed to hydrate the application
	* @returns {never}
	*/
	function hydration_failed() {
		throw new Error(`https://svelte.dev/e/hydration_failed`);
	}
	/**
	* Cannot do `bind:%key%={undefined}` when `%key%` has a fallback value
	* @param {string} key
	* @returns {never}
	*/
	function props_invalid_value(key) {
		throw new Error(`https://svelte.dev/e/props_invalid_value`);
	}
	/**
	* `setContext` must be called when a component first initializes, not in a subsequent effect or after an `await` expression
	* @returns {never}
	*/
	function set_context_after_init() {
		throw new Error(`https://svelte.dev/e/set_context_after_init`);
	}
	/**
	* Property descriptors defined on `$state` objects must contain `value` and always be `enumerable`, `configurable` and `writable`.
	* @returns {never}
	*/
	function state_descriptors_fixed() {
		throw new Error(`https://svelte.dev/e/state_descriptors_fixed`);
	}
	/**
	* Cannot set prototype of `$state` object
	* @returns {never}
	*/
	function state_prototype_fixed() {
		throw new Error(`https://svelte.dev/e/state_prototype_fixed`);
	}
	/**
	* Updating state inside `$derived(...)`, `$inspect(...)` or a template expression is forbidden. If the value should not be reactive, declare it without `$state`
	* @returns {never}
	*/
	function state_unsafe_mutation() {
		throw new Error(`https://svelte.dev/e/state_unsafe_mutation`);
	}
	/**
	* A `<svelte:boundary>` `reset` function cannot be called while an error is still being handled
	* @returns {never}
	*/
	function svelte_boundary_reset_onerror() {
		throw new Error(`https://svelte.dev/e/svelte_boundary_reset_onerror`);
	}
	/**
	* Hydration failed because the initial UI does not match what was rendered on the server. The error occurred near %location%
	* @param {string | undefined | null} [location]
	*/
	function hydration_mismatch(location) {
		console.warn(`https://svelte.dev/e/hydration_mismatch`);
	}
	/**
	* A `<svelte:boundary>` `reset` function only resets the boundary the first time it is called
	*/
	function svelte_boundary_reset_noop() {
		console.warn(`https://svelte.dev/e/svelte_boundary_reset_noop`);
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/dom/hydration.js
	/** @import { TemplateNode } from '#client' */
	/**
	* Use this variable to guard everything related to hydration code so it can be treeshaken out
	* if the user doesn't use the `hydrate` method and these code paths are therefore not needed.
	*/
	var hydrating = false;
	/** @param {boolean} value */
	function set_hydrating(value) {
		hydrating = value;
	}
	/**
	* The node that is currently being hydrated. This starts out as the first node inside the opening
	* <!--[--> comment, and updates each time a component calls `$.child(...)` or `$.sibling(...)`.
	* When entering a block (e.g. `{#if ...}`), `hydrate_node` is the block opening comment; by the
	* time we leave the block it is the closing comment, which serves as the block's anchor.
	* @type {TemplateNode}
	*/
	var hydrate_node;
	/** @param {TemplateNode | null} node */
	function set_hydrate_node(node) {
		if (node === null) {
			hydration_mismatch();
			throw HYDRATION_ERROR;
		}
		return hydrate_node = node;
	}
	function hydrate_next() {
		return set_hydrate_node(/* @__PURE__ */ get_next_sibling(hydrate_node));
	}
	/** @param {TemplateNode} node */
	function reset(node) {
		if (!hydrating) return;
		if (/* @__PURE__ */ get_next_sibling(hydrate_node) !== null) {
			hydration_mismatch();
			throw HYDRATION_ERROR;
		}
		hydrate_node = node;
	}
	function next(count = 1) {
		if (hydrating) {
			var i = count;
			var node = hydrate_node;
			while (i--) node = /* @__PURE__ */ get_next_sibling(node);
			hydrate_node = node;
		}
	}
	/**
	* Skips or removes (depending on {@link remove}) all nodes starting at `hydrate_node` up until the next hydration end comment
	* @param {boolean} remove
	*/
	function skip_nodes(remove = true) {
		var depth = 0;
		var node = hydrate_node;
		while (true) {
			if (node.nodeType === 8) {
				var data = node.data;
				if (data === "]") {
					if (depth === 0) return node;
					depth -= 1;
				} else if (data === "[" || data === "[!" || data[0] === "[" && !isNaN(Number(data.slice(1)))) depth += 1;
			}
			var next = /* @__PURE__ */ get_next_sibling(node);
			if (remove) node.remove();
			node = next;
		}
	}
	/**
	*
	* @param {TemplateNode} node
	*/
	function read_hydration_instruction(node) {
		if (!node || node.nodeType !== 8) {
			hydration_mismatch();
			throw HYDRATION_ERROR;
		}
		return node.data;
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/reactivity/equality.js
	/** @import { Equals } from '#client' */
	/** @type {Equals} */
	function equals(value) {
		return value === this.v;
	}
	/**
	* @param {unknown} a
	* @param {unknown} b
	* @returns {boolean}
	*/
	function safe_not_equal(a, b) {
		return a != a ? b == b : a !== b || a !== null && typeof a === "object" || typeof a === "function";
	}
	/** @type {Equals} */
	function safe_equals(value) {
		return !safe_not_equal(value, this.v);
	}
	//#endregion
	//#region node_modules/svelte/src/internal/flags/index.js
	/** True if experimental.async=true */
	var async_mode_flag = false;
	/** True if we're not certain that we only have Svelte 5 code in the compilation */
	var legacy_mode_flag = false;
	//#endregion
	//#region node_modules/svelte/src/internal/shared/clone.js
	/** @import { Snapshot } from './types' */
	/**
	* In dev, we keep track of which properties could not be cloned. In prod
	* we don't bother, but we keep a dummy array around so that the
	* signature stays the same
	* @type {string[]}
	*/
	var empty = [];
	/**
	* @template T
	* @param {T} value
	* @param {boolean} [skip_warning]
	* @param {boolean} [no_tojson]
	* @returns {Snapshot<T>}
	*/
	function snapshot(value, skip_warning = false, no_tojson = false) {
		return clone$1(value, /* @__PURE__ */ new Map(), "", empty, null, no_tojson);
	}
	/**
	* @template T
	* @param {T} value
	* @param {Map<T, Snapshot<T>>} cloned
	* @param {string} path
	* @param {string[]} paths
	* @param {null | T} [original] The original value, if `value` was produced from a `toJSON` call
	* @param {boolean} [no_tojson]
	* @returns {Snapshot<T>}
	*/
	function clone$1(value, cloned, path, paths, original = null, no_tojson = false) {
		if (typeof value === "object" && value !== null) {
			var unwrapped = cloned.get(value);
			if (unwrapped !== void 0) return unwrapped;
			if (value instanceof Map) return new Map(value);
			if (value instanceof Set) return new Set(value);
			if (is_array(value)) {
				var copy = Array(value.length);
				cloned.set(value, copy);
				if (original !== null) cloned.set(original, copy);
				for (var i = 0; i < value.length; i += 1) {
					var element = value[i];
					if (i in value) copy[i] = clone$1(element, cloned, path, paths, null, no_tojson);
				}
				return copy;
			}
			if (get_prototype_of(value) === object_prototype) {
				/** @type {Snapshot<any>} */
				copy = {};
				cloned.set(value, copy);
				if (original !== null) cloned.set(original, copy);
				for (var key of Object.keys(value)) copy[key] = clone$1(value[key], cloned, path, paths, null, no_tojson);
				return copy;
			}
			if (value instanceof Date) return structuredClone(value);
			if (typeof value.toJSON === "function" && !no_tojson) return clone$1(
				/** @type {T & { toJSON(): any } } */
				value.toJSON(),
				cloned,
				path,
				paths,
				value
			);
		}
		if (value instanceof EventTarget) return value;
		try {
			return structuredClone(value);
		} catch (e) {
			return value;
		}
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/context.js
	/** @import { ComponentContext, DevStackEntry, Effect } from '#client' */
	/** @type {ComponentContext | null} */
	var component_context = null;
	/** @param {ComponentContext | null} context */
	function set_component_context(context) {
		component_context = context;
	}
	/**
	* Retrieves the context that belongs to the closest parent component with the specified `key`.
	* Must be called during component initialisation.
	*
	* [`createContext`](https://svelte.dev/docs/svelte/svelte#createContext) is a type-safe alternative.
	*
	* @template T
	* @param {any} key
	* @returns {T}
	*/
	function getContext(key) {
		return get_or_init_context_map("getContext").get(key);
	}
	/**
	* Associates an arbitrary `context` object with the current component and the specified `key`
	* and returns that object. The context is then available to children of the component
	* (including slotted content) with `getContext`.
	*
	* Like lifecycle functions, this must be called during component initialisation.
	*
	* [`createContext`](https://svelte.dev/docs/svelte/svelte#createContext) is a type-safe alternative.
	*
	* @template T
	* @param {any} key
	* @param {T} context
	* @returns {T}
	*/
	function setContext(key, context) {
		const context_map = get_or_init_context_map("setContext");
		if (async_mode_flag) {
			var flags = active_effect.f;
			if (!(!active_reaction && (flags & 32) !== 0 && !component_context.i)) set_context_after_init();
		}
		context_map.set(key, context);
		return context;
	}
	/**
	* @param {Record<string, unknown>} props
	* @param {any} runes
	* @param {Function} [fn]
	* @returns {void}
	*/
	function push(props, runes = false, fn) {
		component_context = {
			p: component_context,
			i: false,
			c: null,
			e: null,
			s: props,
			x: null,
			r: active_effect,
			l: legacy_mode_flag && !runes ? {
				s: null,
				u: null,
				$: []
			} : null
		};
	}
	/**
	* @template {Record<string, any>} T
	* @param {T} [component]
	* @returns {T}
	*/
	function pop(component) {
		var context = component_context;
		var effects = context.e;
		if (effects !== null) {
			context.e = null;
			for (var fn of effects) create_user_effect(fn);
		}
		if (component !== void 0) context.x = component;
		context.i = true;
		component_context = context.p;
		return component ?? {};
	}
	/** @returns {boolean} */
	function is_runes() {
		return !legacy_mode_flag || component_context !== null && component_context.l === null;
	}
	/**
	* @param {string} name
	* @returns {Map<unknown, unknown>}
	*/
	function get_or_init_context_map(name) {
		if (component_context === null) lifecycle_outside_component(name);
		return component_context.c ??= new Map(get_parent_context(component_context) || void 0);
	}
	/**
	* @param {ComponentContext} component_context
	* @returns {Map<unknown, unknown> | null}
	*/
	function get_parent_context(component_context) {
		let parent = component_context.p;
		while (parent !== null) {
			const context_map = parent.c;
			if (context_map !== null) return context_map;
			parent = parent.p;
		}
		return null;
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/dom/task.js
	/** @type {Array<() => void>} */
	var micro_tasks = [];
	function run_micro_tasks() {
		var tasks = micro_tasks;
		micro_tasks = [];
		run_all(tasks);
	}
	/**
	* @param {() => void} fn
	*/
	function queue_micro_task(fn) {
		if (micro_tasks.length === 0 && !is_flushing_sync) {
			var tasks = micro_tasks;
			queueMicrotask(() => {
				if (tasks === micro_tasks) run_micro_tasks();
			});
		}
		micro_tasks.push(fn);
	}
	/**
	* Synchronously run any queued tasks.
	*/
	function flush_tasks() {
		while (micro_tasks.length > 0) run_micro_tasks();
	}
	/**
	* @param {unknown} error
	*/
	function handle_error(error) {
		var effect = active_effect;
		if (effect === null) {
			/** @type {Derived} */ active_reaction.f |= ERROR_VALUE;
			return error;
		}
		if ((effect.f & 32768) === 0 && (effect.f & 4) === 0) throw error;
		invoke_error_boundary(error, effect);
	}
	/**
	* @param {unknown} error
	* @param {Effect | null} effect
	*/
	function invoke_error_boundary(error, effect) {
		while (effect !== null) {
			if ((effect.f & 128) !== 0) {
				if ((effect.f & 32768) === 0) throw error;
				try {
					/** @type {Boundary} */ effect.b.error(error);
					return;
				} catch (e) {
					error = e;
				}
			}
			effect = effect.parent;
		}
		throw error;
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/reactivity/status.js
	/** @import { Derived, Signal } from '#client' */
	var STATUS_MASK = ~(DIRTY | MAYBE_DIRTY | CLEAN);
	/**
	* @param {Signal} signal
	* @param {number} status
	*/
	function set_signal_status(signal, status) {
		signal.f = signal.f & STATUS_MASK | status;
	}
	/**
	* Set a derived's status to CLEAN or MAYBE_DIRTY based on its connection state.
	* @param {Derived} derived
	*/
	function update_derived_status(derived) {
		if ((derived.f & 512) !== 0 || derived.deps === null) set_signal_status(derived, CLEAN);
		else set_signal_status(derived, MAYBE_DIRTY);
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/reactivity/utils.js
	/** @import { Derived, Effect, Value } from '#client' */
	/**
	* @param {Value[] | null} deps
	*/
	function clear_marked(deps) {
		if (deps === null) return;
		for (const dep of deps) {
			if ((dep.f & 2) === 0 || (dep.f & 65536) === 0) continue;
			dep.f ^= WAS_MARKED;
			clear_marked(
				/** @type {Derived} */
				dep.deps
			);
		}
	}
	/**
	* @param {Effect} effect
	* @param {Set<Effect>} dirty_effects
	* @param {Set<Effect>} maybe_dirty_effects
	*/
	function defer_effect(effect, dirty_effects, maybe_dirty_effects) {
		if ((effect.f & 2048) !== 0) dirty_effects.add(effect);
		else if ((effect.f & 4096) !== 0) maybe_dirty_effects.add(effect);
		clear_marked(effect.deps);
		set_signal_status(effect, CLEAN);
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/reactivity/store.js
	/**
	* We set this to `true` when updating a store so that we correctly
	* schedule effects if the update takes place inside a `$:` effect
	*/
	var legacy_is_updating_store = false;
	/**
	* Whether or not the prop currently being read is a store binding, as in
	* `<Child bind:x={$y} />`. If it is, we treat the prop as mutable even in
	* runes mode, and skip `binding_property_non_reactive` validation
	*/
	var is_store_binding = false;
	/**
	* Returns a tuple that indicates whether `fn()` reads a prop that is a store binding.
	* Used to prevent `binding_property_non_reactive` validation false positives and
	* ensure that these props are treated as mutable even in runes mode
	* @template T
	* @param {() => T} fn
	* @returns {[T, boolean]}
	*/
	function capture_store_binding(fn) {
		var previous_is_store_binding = is_store_binding;
		try {
			is_store_binding = false;
			return [fn(), is_store_binding];
		} finally {
			is_store_binding = previous_is_store_binding;
		}
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/reactivity/batch.js
	/** @import { Fork } from 'svelte' */
	/** @import { Derived, Effect, Reaction, Source, Value } from '#client' */
	/** @type {Set<Batch>} */
	var batches = /* @__PURE__ */ new Set();
	/** @type {Batch | null} */
	var current_batch = null;
	/**
	* This is needed to avoid overwriting inputs
	* @type {Batch | null}
	*/
	var previous_batch = null;
	/**
	* When time travelling (i.e. working in one batch, while other batches
	* still have ongoing work), we ignore the real values of affected
	* signals in favour of their values within the batch
	* @type {Map<Value, any> | null}
	*/
	var batch_values = null;
	/** @type {Effect | null} */
	var last_scheduled_effect = null;
	var is_flushing_sync = false;
	var is_processing = false;
	/**
	* During traversal, this is an array. Newly created effects are (if not immediately
	* executed) pushed to this array, rather than going through the scheduling
	* rigamarole that would cause another turn of the flush loop.
	* @type {Effect[] | null}
	*/
	var collected_effects = null;
	/**
	* An array of effects that are marked during traversal as a result of a `set`
	* (not `internal_set`) call. These will be added to the next batch and
	* trigger another `batch.process()`
	* @type {Effect[] | null}
	* @deprecated when we get rid of legacy mode and stores, we can get rid of this
	*/
	var legacy_updates = null;
	var flush_count = 0;
	var uid = 1;
	var Batch = class Batch {
		id = uid++;
		/**
		* The current values of any sources that are updated in this batch
		* They keys of this map are identical to `this.#previous`
		* @type {Map<Source, any>}
		*/
		current = /* @__PURE__ */ new Map();
		/**
		* The values of any sources that are updated in this batch _before_ those updates took place.
		* They keys of this map are identical to `this.#current`
		* @type {Map<Source, any>}
		*/
		previous = /* @__PURE__ */ new Map();
		/**
		* When the batch is committed (and the DOM is updated), we need to remove old branches
		* and append new ones by calling the functions added inside (if/each/key/etc) blocks
		* @type {Set<(batch: Batch) => void>}
		*/
		#commit_callbacks = /* @__PURE__ */ new Set();
		/**
		* If a fork is discarded, we need to destroy any effects that are no longer needed
		* @type {Set<(batch: Batch) => void>}
		*/
		#discard_callbacks = /* @__PURE__ */ new Set();
		/**
		* The number of async effects that are currently in flight
		*/
		#pending = 0;
		/**
		* The number of async effects that are currently in flight, _not_ inside a pending boundary
		*/
		#blocking_pending = 0;
		/**
		* A deferred that resolves when the batch is committed, used with `settled()`
		* TODO replace with Promise.withResolvers once supported widely enough
		* @type {{ promise: Promise<void>, resolve: (value?: any) => void, reject: (reason: unknown) => void } | null}
		*/
		#deferred = null;
		/**
		* The root effects that need to be flushed
		* @type {Effect[]}
		*/
		#roots = [];
		/**
		* Deferred effects (which run after async work has completed) that are DIRTY
		* @type {Set<Effect>}
		*/
		#dirty_effects = /* @__PURE__ */ new Set();
		/**
		* Deferred effects that are MAYBE_DIRTY
		* @type {Set<Effect>}
		*/
		#maybe_dirty_effects = /* @__PURE__ */ new Set();
		/**
		* A map of branches that still exist, but will be destroyed when this batch
		* is committed — we skip over these during `process`.
		* The value contains child effects that were dirty/maybe_dirty before being reset,
		* so they can be rescheduled if the branch survives.
		* @type {Map<Effect, { d: Effect[], m: Effect[] }>}
		*/
		#skipped_branches = /* @__PURE__ */ new Map();
		is_fork = false;
		#decrement_queued = false;
		#is_deferred() {
			return this.is_fork || this.#blocking_pending > 0;
		}
		/**
		* Add an effect to the #skipped_branches map and reset its children
		* @param {Effect} effect
		*/
		skip_effect(effect) {
			if (!this.#skipped_branches.has(effect)) this.#skipped_branches.set(effect, {
				d: [],
				m: []
			});
		}
		/**
		* Remove an effect from the #skipped_branches map and reschedule
		* any tracked dirty/maybe_dirty child effects
		* @param {Effect} effect
		*/
		unskip_effect(effect) {
			var tracked = this.#skipped_branches.get(effect);
			if (tracked) {
				this.#skipped_branches.delete(effect);
				for (var e of tracked.d) {
					set_signal_status(e, DIRTY);
					this.schedule(e);
				}
				for (e of tracked.m) {
					set_signal_status(e, MAYBE_DIRTY);
					this.schedule(e);
				}
			}
		}
		#process() {
			if (flush_count++ > 1e3) {
				batches.delete(this);
				infinite_loop_guard();
			}
			if (!this.#is_deferred()) {
				for (const e of this.#dirty_effects) {
					this.#maybe_dirty_effects.delete(e);
					set_signal_status(e, DIRTY);
					this.schedule(e);
				}
				for (const e of this.#maybe_dirty_effects) {
					set_signal_status(e, MAYBE_DIRTY);
					this.schedule(e);
				}
			}
			const roots = this.#roots;
			this.#roots = [];
			this.apply();
			/** @type {Effect[]} */
			var effects = collected_effects = [];
			/** @type {Effect[]} */
			var render_effects = [];
			/**
			* @type {Effect[]}
			* @deprecated when we get rid of legacy mode and stores, we can get rid of this
			*/
			var updates = legacy_updates = [];
			for (const root of roots) try {
				this.#traverse(root, effects, render_effects);
			} catch (e) {
				reset_all(root);
				throw e;
			}
			current_batch = null;
			if (updates.length > 0) {
				var batch = Batch.ensure();
				for (const e of updates) batch.schedule(e);
			}
			collected_effects = null;
			legacy_updates = null;
			if (this.#is_deferred()) {
				this.#defer_effects(render_effects);
				this.#defer_effects(effects);
				for (const [e, t] of this.#skipped_branches) reset_branch(e, t);
			} else {
				if (this.#pending === 0) batches.delete(this);
				this.#dirty_effects.clear();
				this.#maybe_dirty_effects.clear();
				for (const fn of this.#commit_callbacks) fn(this);
				this.#commit_callbacks.clear();
				previous_batch = this;
				flush_queued_effects(render_effects);
				flush_queued_effects(effects);
				previous_batch = null;
				this.#deferred?.resolve();
			}
			var next_batch = current_batch;
			if (this.#roots.length > 0) {
				const batch = next_batch ??= this;
				batch.#roots.push(...this.#roots.filter((r) => !batch.#roots.includes(r)));
			}
			if (next_batch !== null) {
				batches.add(next_batch);
				next_batch.#process();
			}
			if (!batches.has(this)) this.#commit();
		}
		/**
		* Traverse the effect tree, executing effects or stashing
		* them for later execution as appropriate
		* @param {Effect} root
		* @param {Effect[]} effects
		* @param {Effect[]} render_effects
		*/
		#traverse(root, effects, render_effects) {
			root.f ^= CLEAN;
			var effect = root.first;
			while (effect !== null) {
				var flags = effect.f;
				var is_branch = (flags & 96) !== 0;
				if (!(is_branch && (flags & 1024) !== 0 || (flags & 8192) !== 0 || this.#skipped_branches.has(effect)) && effect.fn !== null) {
					if (is_branch) effect.f ^= CLEAN;
					else if ((flags & 4) !== 0) effects.push(effect);
					else if (async_mode_flag && (flags & 16777224) !== 0) render_effects.push(effect);
					else if (is_dirty(effect)) {
						if ((flags & 16) !== 0) this.#maybe_dirty_effects.add(effect);
						update_effect(effect);
					}
					var child = effect.first;
					if (child !== null) {
						effect = child;
						continue;
					}
				}
				while (effect !== null) {
					var next = effect.next;
					if (next !== null) {
						effect = next;
						break;
					}
					effect = effect.parent;
				}
			}
		}
		/**
		* @param {Effect[]} effects
		*/
		#defer_effects(effects) {
			for (var i = 0; i < effects.length; i += 1) defer_effect(effects[i], this.#dirty_effects, this.#maybe_dirty_effects);
		}
		/**
		* Associate a change to a given source with the current
		* batch, noting its previous and current values
		* @param {Source} source
		* @param {any} old_value
		*/
		capture(source, old_value) {
			if (old_value !== UNINITIALIZED && !this.previous.has(source)) this.previous.set(source, old_value);
			if ((source.f & 8388608) === 0) {
				this.current.set(source, source.v);
				batch_values?.set(source, source.v);
			}
		}
		activate() {
			current_batch = this;
		}
		deactivate() {
			current_batch = null;
			batch_values = null;
		}
		flush() {
			try {
				is_processing = true;
				current_batch = this;
				this.#process();
			} finally {
				flush_count = 0;
				last_scheduled_effect = null;
				collected_effects = null;
				legacy_updates = null;
				is_processing = false;
				current_batch = null;
				batch_values = null;
				old_values.clear();
			}
		}
		discard() {
			for (const fn of this.#discard_callbacks) fn(this);
			this.#discard_callbacks.clear();
			batches.delete(this);
		}
		#commit() {
			for (const batch of batches) {
				var is_earlier = batch.id < this.id;
				/** @type {Source[]} */
				var sources = [];
				for (const [source, value] of this.current) {
					if (batch.current.has(source)) if (is_earlier && value !== batch.current.get(source)) batch.current.set(source, value);
					else continue;
					sources.push(source);
				}
				var others = [...batch.current.keys()].filter((s) => !this.current.has(s));
				if (others.length === 0) {
					if (is_earlier) batch.discard();
				} else if (sources.length > 0) {
					batch.activate();
					/** @type {Set<Value>} */
					var marked = /* @__PURE__ */ new Set();
					/** @type {Map<Reaction, boolean>} */
					var checked = /* @__PURE__ */ new Map();
					for (var source of sources) mark_effects(source, others, marked, checked);
					if (batch.#roots.length > 0) {
						batch.apply();
						for (var root of batch.#roots) batch.#traverse(root, [], []);
						batch.#roots = [];
					}
					batch.deactivate();
				}
			}
		}
		/**
		*
		* @param {boolean} blocking
		*/
		increment(blocking) {
			this.#pending += 1;
			if (blocking) this.#blocking_pending += 1;
		}
		/**
		* @param {boolean} blocking
		* @param {boolean} skip - whether to skip updates (because this is triggered by a stale reaction)
		*/
		decrement(blocking, skip) {
			this.#pending -= 1;
			if (blocking) this.#blocking_pending -= 1;
			if (this.#decrement_queued || skip) return;
			this.#decrement_queued = true;
			queue_micro_task(() => {
				this.#decrement_queued = false;
				this.flush();
			});
		}
		/**
		* @param {Set<Effect>} dirty_effects
		* @param {Set<Effect>} maybe_dirty_effects
		*/
		transfer_effects(dirty_effects, maybe_dirty_effects) {
			for (const e of dirty_effects) this.#dirty_effects.add(e);
			for (const e of maybe_dirty_effects) this.#maybe_dirty_effects.add(e);
			dirty_effects.clear();
			maybe_dirty_effects.clear();
		}
		/** @param {(batch: Batch) => void} fn */
		oncommit(fn) {
			this.#commit_callbacks.add(fn);
		}
		/** @param {(batch: Batch) => void} fn */
		ondiscard(fn) {
			this.#discard_callbacks.add(fn);
		}
		settled() {
			return (this.#deferred ??= deferred()).promise;
		}
		static ensure() {
			if (current_batch === null) {
				const batch = current_batch = new Batch();
				if (!is_processing) {
					batches.add(current_batch);
					if (!is_flushing_sync) queue_micro_task(() => {
						if (current_batch !== batch) return;
						batch.flush();
					});
				}
			}
			return current_batch;
		}
		apply() {
			if (!async_mode_flag || !this.is_fork && batches.size === 1) {
				batch_values = null;
				return;
			}
			batch_values = new Map(this.current);
			for (const batch of batches) {
				if (batch === this || batch.is_fork) continue;
				for (const [source, previous] of batch.previous) if (!batch_values.has(source)) batch_values.set(source, previous);
			}
		}
		/**
		*
		* @param {Effect} effect
		*/
		schedule(effect) {
			last_scheduled_effect = effect;
			if (effect.b?.is_pending && (effect.f & 16777228) !== 0 && (effect.f & 32768) === 0) {
				effect.b.defer_effect(effect);
				return;
			}
			var e = effect;
			while (e.parent !== null) {
				e = e.parent;
				var flags = e.f;
				if (collected_effects !== null && e === active_effect) {
					if (async_mode_flag) return;
					if ((active_reaction === null || (active_reaction.f & 2) === 0) && !legacy_is_updating_store) return;
				}
				if ((flags & 96) !== 0) {
					if ((flags & 1024) === 0) return;
					e.f ^= CLEAN;
				}
			}
			this.#roots.push(e);
		}
	};
	/**
	* Synchronously flush any pending updates.
	* Returns void if no callback is provided, otherwise returns the result of calling the callback.
	* @template [T=void]
	* @param {(() => T) | undefined} [fn]
	* @returns {T}
	*/
	function flushSync(fn) {
		var was_flushing_sync = is_flushing_sync;
		is_flushing_sync = true;
		try {
			var result;
			if (fn) {
				if (current_batch !== null && !current_batch.is_fork) current_batch.flush();
				result = fn();
			}
			while (true) {
				flush_tasks();
				if (current_batch === null) return result;
				current_batch.flush();
			}
		} finally {
			is_flushing_sync = was_flushing_sync;
		}
	}
	function infinite_loop_guard() {
		try {
			effect_update_depth_exceeded();
		} catch (error) {
			invoke_error_boundary(error, last_scheduled_effect);
		}
	}
	/** @type {Set<Effect> | null} */
	var eager_block_effects = null;
	/**
	* @param {Array<Effect>} effects
	* @returns {void}
	*/
	function flush_queued_effects(effects) {
		var length = effects.length;
		if (length === 0) return;
		var i = 0;
		while (i < length) {
			var effect = effects[i++];
			if ((effect.f & 24576) === 0 && is_dirty(effect)) {
				eager_block_effects = /* @__PURE__ */ new Set();
				update_effect(effect);
				if (effect.deps === null && effect.first === null && effect.nodes === null && effect.teardown === null && effect.ac === null) unlink_effect(effect);
				if (eager_block_effects?.size > 0) {
					old_values.clear();
					for (const e of eager_block_effects) {
						if ((e.f & 24576) !== 0) continue;
						/** @type {Effect[]} */
						const ordered_effects = [e];
						let ancestor = e.parent;
						while (ancestor !== null) {
							if (eager_block_effects.has(ancestor)) {
								eager_block_effects.delete(ancestor);
								ordered_effects.push(ancestor);
							}
							ancestor = ancestor.parent;
						}
						for (let j = ordered_effects.length - 1; j >= 0; j--) {
							const e = ordered_effects[j];
							if ((e.f & 24576) !== 0) continue;
							update_effect(e);
						}
					}
					eager_block_effects.clear();
				}
			}
		}
		eager_block_effects = null;
	}
	/**
	* This is similar to `mark_reactions`, but it only marks async/block effects
	* depending on `value` and at least one of the other `sources`, so that
	* these effects can re-run after another batch has been committed
	* @param {Value} value
	* @param {Source[]} sources
	* @param {Set<Value>} marked
	* @param {Map<Reaction, boolean>} checked
	*/
	function mark_effects(value, sources, marked, checked) {
		if (marked.has(value)) return;
		marked.add(value);
		if (value.reactions !== null) for (const reaction of value.reactions) {
			const flags = reaction.f;
			if ((flags & 2) !== 0) mark_effects(reaction, sources, marked, checked);
			else if ((flags & 4194320) !== 0 && (flags & 2048) === 0 && depends_on(reaction, sources, checked)) {
				set_signal_status(reaction, DIRTY);
				schedule_effect(reaction);
			}
		}
	}
	/**
	* @param {Reaction} reaction
	* @param {Source[]} sources
	* @param {Map<Reaction, boolean>} checked
	*/
	function depends_on(reaction, sources, checked) {
		const depends = checked.get(reaction);
		if (depends !== void 0) return depends;
		if (reaction.deps !== null) for (const dep of reaction.deps) {
			if (includes.call(sources, dep)) return true;
			if ((dep.f & 2) !== 0 && depends_on(dep, sources, checked)) {
				checked.set(dep, true);
				return true;
			}
		}
		checked.set(reaction, false);
		return false;
	}
	/**
	* @param {Effect} effect
	* @returns {void}
	*/
	function schedule_effect(effect) {
		/** @type {Batch} */ current_batch.schedule(effect);
	}
	/**
	* Mark all the effects inside a skipped branch CLEAN, so that
	* they can be correctly rescheduled later. Tracks dirty and maybe_dirty
	* effects so they can be rescheduled if the branch survives.
	* @param {Effect} effect
	* @param {{ d: Effect[], m: Effect[] }} tracked
	*/
	function reset_branch(effect, tracked) {
		if ((effect.f & 32) !== 0 && (effect.f & 1024) !== 0) return;
		if ((effect.f & 2048) !== 0) tracked.d.push(effect);
		else if ((effect.f & 4096) !== 0) tracked.m.push(effect);
		set_signal_status(effect, CLEAN);
		var e = effect.first;
		while (e !== null) {
			reset_branch(e, tracked);
			e = e.next;
		}
	}
	/**
	* Mark an entire effect tree clean following an error
	* @param {Effect} effect
	*/
	function reset_all(effect) {
		set_signal_status(effect, CLEAN);
		var e = effect.first;
		while (e !== null) {
			reset_all(e);
			e = e.next;
		}
	}
	//#endregion
	//#region node_modules/svelte/src/reactivity/create-subscriber.js
	/**
	* Returns a `subscribe` function that integrates external event-based systems with Svelte's reactivity.
	* It's particularly useful for integrating with web APIs like `MediaQuery`, `IntersectionObserver`, or `WebSocket`.
	*
	* If `subscribe` is called inside an effect (including indirectly, for example inside a getter),
	* the `start` callback will be called with an `update` function. Whenever `update` is called, the effect re-runs.
	*
	* If `start` returns a cleanup function, it will be called when the effect is destroyed.
	*
	* If `subscribe` is called in multiple effects, `start` will only be called once as long as the effects
	* are active, and the returned teardown function will only be called when all effects are destroyed.
	*
	* It's best understood with an example. Here's an implementation of [`MediaQuery`](https://svelte.dev/docs/svelte/svelte-reactivity#MediaQuery):
	*
	* ```js
	* import { createSubscriber } from 'svelte/reactivity';
	* import { on } from 'svelte/events';
	*
	* export class MediaQuery {
	* 	#query;
	* 	#subscribe;
	*
	* 	constructor(query) {
	* 		this.#query = window.matchMedia(`(${query})`);
	*
	* 		this.#subscribe = createSubscriber((update) => {
	* 			// when the `change` event occurs, re-run any effects that read `this.current`
	* 			const off = on(this.#query, 'change', update);
	*
	* 			// stop listening when all the effects are destroyed
	* 			return () => off();
	* 		});
	* 	}
	*
	* 	get current() {
	* 		// This makes the getter reactive, if read in an effect
	* 		this.#subscribe();
	*
	* 		// Return the current state of the query, whether or not we're in an effect
	* 		return this.#query.matches;
	* 	}
	* }
	* ```
	* @param {(update: () => void) => (() => void) | void} start
	* @since 5.7.0
	*/
	function createSubscriber(start) {
		let subscribers = 0;
		let version = source(0);
		/** @type {(() => void) | void} */
		let stop;
		return () => {
			if (effect_tracking()) {
				get(version);
				render_effect(() => {
					if (subscribers === 0) stop = untrack(() => start(() => increment(version)));
					subscribers += 1;
					return () => {
						queue_micro_task(() => {
							subscribers -= 1;
							if (subscribers === 0) {
								stop?.();
								stop = void 0;
								increment(version);
							}
						});
					};
				});
			}
		};
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/dom/blocks/boundary.js
	/** @import { Effect, Source, TemplateNode, } from '#client' */
	/**
	* @typedef {{
	* 	 onerror?: (error: unknown, reset: () => void) => void;
	*   failed?: (anchor: Node, error: () => unknown, reset: () => () => void) => void;
	*   pending?: (anchor: Node) => void;
	* }} BoundaryProps
	*/
	var flags = EFFECT_TRANSPARENT | EFFECT_PRESERVED;
	/**
	* @param {TemplateNode} node
	* @param {BoundaryProps} props
	* @param {((anchor: Node) => void)} children
	* @param {((error: unknown) => unknown) | undefined} [transform_error]
	* @returns {void}
	*/
	function boundary(node, props, children, transform_error) {
		new Boundary(node, props, children, transform_error);
	}
	var Boundary = class {
		/** @type {Boundary | null} */
		parent;
		is_pending = false;
		/**
		* API-level transformError transform function. Transforms errors before they reach the `failed` snippet.
		* Inherited from parent boundary, or defaults to identity.
		* @type {(error: unknown) => unknown}
		*/
		transform_error;
		/** @type {TemplateNode} */
		#anchor;
		/** @type {TemplateNode | null} */
		#hydrate_open = hydrating ? hydrate_node : null;
		/** @type {BoundaryProps} */
		#props;
		/** @type {((anchor: Node) => void)} */
		#children;
		/** @type {Effect} */
		#effect;
		/** @type {Effect | null} */
		#main_effect = null;
		/** @type {Effect | null} */
		#pending_effect = null;
		/** @type {Effect | null} */
		#failed_effect = null;
		/** @type {DocumentFragment | null} */
		#offscreen_fragment = null;
		#local_pending_count = 0;
		#pending_count = 0;
		#pending_count_update_queued = false;
		/** @type {Set<Effect>} */
		#dirty_effects = /* @__PURE__ */ new Set();
		/** @type {Set<Effect>} */
		#maybe_dirty_effects = /* @__PURE__ */ new Set();
		/**
		* A source containing the number of pending async deriveds/expressions.
		* Only created if `$effect.pending()` is used inside the boundary,
		* otherwise updating the source results in needless `Batch.ensure()`
		* calls followed by no-op flushes
		* @type {Source<number> | null}
		*/
		#effect_pending = null;
		#effect_pending_subscriber = createSubscriber(() => {
			this.#effect_pending = source(this.#local_pending_count);
			return () => {
				this.#effect_pending = null;
			};
		});
		/**
		* @param {TemplateNode} node
		* @param {BoundaryProps} props
		* @param {((anchor: Node) => void)} children
		* @param {((error: unknown) => unknown) | undefined} [transform_error]
		*/
		constructor(node, props, children, transform_error) {
			this.#anchor = node;
			this.#props = props;
			this.#children = (anchor) => {
				var effect = active_effect;
				effect.b = this;
				effect.f |= 128;
				children(anchor);
			};
			this.parent = active_effect.b;
			this.transform_error = transform_error ?? this.parent?.transform_error ?? ((e) => e);
			this.#effect = block(() => {
				if (hydrating) {
					const comment = this.#hydrate_open;
					hydrate_next();
					const server_rendered_pending = comment.data === "[!";
					if (comment.data.startsWith("[?")) {
						const serialized_error = JSON.parse(comment.data.slice(2));
						this.#hydrate_failed_content(serialized_error);
					} else if (server_rendered_pending) this.#hydrate_pending_content();
					else this.#hydrate_resolved_content();
				} else this.#render();
			}, flags);
			if (hydrating) this.#anchor = hydrate_node;
		}
		#hydrate_resolved_content() {
			try {
				this.#main_effect = branch(() => this.#children(this.#anchor));
			} catch (error) {
				this.error(error);
			}
		}
		/**
		* @param {unknown} error The deserialized error from the server's hydration comment
		*/
		#hydrate_failed_content(error) {
			const failed = this.#props.failed;
			if (!failed) return;
			this.#failed_effect = branch(() => {
				failed(this.#anchor, () => error, () => () => {});
			});
		}
		#hydrate_pending_content() {
			const pending = this.#props.pending;
			if (!pending) return;
			this.is_pending = true;
			this.#pending_effect = branch(() => pending(this.#anchor));
			queue_micro_task(() => {
				var fragment = this.#offscreen_fragment = document.createDocumentFragment();
				var anchor = create_text();
				fragment.append(anchor);
				this.#main_effect = this.#run(() => {
					return branch(() => this.#children(anchor));
				});
				if (this.#pending_count === 0) {
					this.#anchor.before(fragment);
					this.#offscreen_fragment = null;
					pause_effect(this.#pending_effect, () => {
						this.#pending_effect = null;
					});
					this.#resolve(current_batch);
				}
			});
		}
		#render() {
			try {
				this.is_pending = this.has_pending_snippet();
				this.#pending_count = 0;
				this.#local_pending_count = 0;
				this.#main_effect = branch(() => {
					this.#children(this.#anchor);
				});
				if (this.#pending_count > 0) {
					var fragment = this.#offscreen_fragment = document.createDocumentFragment();
					move_effect(this.#main_effect, fragment);
					const pending = this.#props.pending;
					this.#pending_effect = branch(() => pending(this.#anchor));
				} else this.#resolve(current_batch);
			} catch (error) {
				this.error(error);
			}
		}
		/**
		* @param {Batch} batch
		*/
		#resolve(batch) {
			this.is_pending = false;
			batch.transfer_effects(this.#dirty_effects, this.#maybe_dirty_effects);
		}
		/**
		* Defer an effect inside a pending boundary until the boundary resolves
		* @param {Effect} effect
		*/
		defer_effect(effect) {
			defer_effect(effect, this.#dirty_effects, this.#maybe_dirty_effects);
		}
		/**
		* Returns `false` if the effect exists inside a boundary whose pending snippet is shown
		* @returns {boolean}
		*/
		is_rendered() {
			return !this.is_pending && (!this.parent || this.parent.is_rendered());
		}
		has_pending_snippet() {
			return !!this.#props.pending;
		}
		/**
		* @template T
		* @param {() => T} fn
		*/
		#run(fn) {
			var previous_effect = active_effect;
			var previous_reaction = active_reaction;
			var previous_ctx = component_context;
			set_active_effect(this.#effect);
			set_active_reaction(this.#effect);
			set_component_context(this.#effect.ctx);
			try {
				Batch.ensure();
				return fn();
			} catch (e) {
				handle_error(e);
				return null;
			} finally {
				set_active_effect(previous_effect);
				set_active_reaction(previous_reaction);
				set_component_context(previous_ctx);
			}
		}
		/**
		* Updates the pending count associated with the currently visible pending snippet,
		* if any, such that we can replace the snippet with content once work is done
		* @param {1 | -1} d
		* @param {Batch} batch
		*/
		#update_pending_count(d, batch) {
			if (!this.has_pending_snippet()) {
				if (this.parent) this.parent.#update_pending_count(d, batch);
				return;
			}
			this.#pending_count += d;
			if (this.#pending_count === 0) {
				this.#resolve(batch);
				if (this.#pending_effect) pause_effect(this.#pending_effect, () => {
					this.#pending_effect = null;
				});
				if (this.#offscreen_fragment) {
					this.#anchor.before(this.#offscreen_fragment);
					this.#offscreen_fragment = null;
				}
			}
		}
		/**
		* Update the source that powers `$effect.pending()` inside this boundary,
		* and controls when the current `pending` snippet (if any) is removed.
		* Do not call from inside the class
		* @param {1 | -1} d
		* @param {Batch} batch
		*/
		update_pending_count(d, batch) {
			this.#update_pending_count(d, batch);
			this.#local_pending_count += d;
			if (!this.#effect_pending || this.#pending_count_update_queued) return;
			this.#pending_count_update_queued = true;
			queue_micro_task(() => {
				this.#pending_count_update_queued = false;
				if (this.#effect_pending) internal_set(this.#effect_pending, this.#local_pending_count);
			});
		}
		get_effect_pending() {
			this.#effect_pending_subscriber();
			return get(this.#effect_pending);
		}
		/** @param {unknown} error */
		error(error) {
			var onerror = this.#props.onerror;
			let failed = this.#props.failed;
			if (!onerror && !failed) throw error;
			if (this.#main_effect) {
				destroy_effect(this.#main_effect);
				this.#main_effect = null;
			}
			if (this.#pending_effect) {
				destroy_effect(this.#pending_effect);
				this.#pending_effect = null;
			}
			if (this.#failed_effect) {
				destroy_effect(this.#failed_effect);
				this.#failed_effect = null;
			}
			if (hydrating) {
				set_hydrate_node(this.#hydrate_open);
				next();
				set_hydrate_node(skip_nodes());
			}
			var did_reset = false;
			var calling_on_error = false;
			const reset = () => {
				if (did_reset) {
					svelte_boundary_reset_noop();
					return;
				}
				did_reset = true;
				if (calling_on_error) svelte_boundary_reset_onerror();
				if (this.#failed_effect !== null) pause_effect(this.#failed_effect, () => {
					this.#failed_effect = null;
				});
				this.#run(() => {
					this.#render();
				});
			};
			/** @param {unknown} transformed_error */
			const handle_error_result = (transformed_error) => {
				try {
					calling_on_error = true;
					onerror?.(transformed_error, reset);
					calling_on_error = false;
				} catch (error) {
					invoke_error_boundary(error, this.#effect && this.#effect.parent);
				}
				if (failed) this.#failed_effect = this.#run(() => {
					try {
						return branch(() => {
							var effect = active_effect;
							effect.b = this;
							effect.f |= 128;
							failed(this.#anchor, () => transformed_error, () => reset);
						});
					} catch (error) {
						invoke_error_boundary(error, this.#effect.parent);
						return null;
					}
				});
			};
			queue_micro_task(() => {
				/** @type {unknown} */
				var result;
				try {
					result = this.transform_error(error);
				} catch (e) {
					invoke_error_boundary(e, this.#effect && this.#effect.parent);
					return;
				}
				if (result !== null && typeof result === "object" && typeof result.then === "function")
 /** @type {any} */ result.then(
					handle_error_result,
					/** @param {unknown} e */
					(e) => invoke_error_boundary(e, this.#effect && this.#effect.parent)
				);
				else handle_error_result(result);
			});
		}
	};
	//#endregion
	//#region node_modules/svelte/src/internal/client/reactivity/async.js
	/** @import { Blocker, Effect, Value } from '#client' */
	/**
	* @param {Blocker[]} blockers
	* @param {Array<() => any>} sync
	* @param {Array<() => Promise<any>>} async
	* @param {(values: Value[]) => any} fn
	*/
	function flatten(blockers, sync, async, fn) {
		const d = is_runes() ? derived : derived_safe_equal;
		var pending = blockers.filter((b) => !b.settled);
		if (async.length === 0 && pending.length === 0) {
			fn(sync.map(d));
			return;
		}
		var parent = active_effect;
		var restore = capture();
		var blocker_promise = pending.length === 1 ? pending[0].promise : pending.length > 1 ? Promise.all(pending.map((b) => b.promise)) : null;
		/** @param {Value[]} values */
		function finish(values) {
			restore();
			try {
				fn(values);
			} catch (error) {
				if ((parent.f & 16384) === 0) invoke_error_boundary(error, parent);
			}
			unset_context();
		}
		if (async.length === 0) {
			/** @type {Promise<any>} */ blocker_promise.then(() => finish(sync.map(d)));
			return;
		}
		var decrement_pending = increment_pending();
		function run() {
			Promise.all(async.map((expression) => /* @__PURE__ */ async_derived(expression))).then((result) => finish([...sync.map(d), ...result])).catch((error) => invoke_error_boundary(error, parent)).finally(() => decrement_pending());
		}
		if (blocker_promise) blocker_promise.then(() => {
			restore();
			run();
			unset_context();
		});
		else run();
	}
	/**
	* Captures the current effect context so that we can restore it after
	* some asynchronous work has happened (so that e.g. `await a + b`
	* causes `b` to be registered as a dependency).
	*/
	function capture() {
		var previous_effect = active_effect;
		var previous_reaction = active_reaction;
		var previous_component_context = component_context;
		var previous_batch = current_batch;
		return function restore(activate_batch = true) {
			set_active_effect(previous_effect);
			set_active_reaction(previous_reaction);
			set_component_context(previous_component_context);
			if (activate_batch && (previous_effect.f & 16384) === 0) {
				previous_batch?.activate();
				previous_batch?.apply();
			}
		};
	}
	function unset_context(deactivate_batch = true) {
		set_active_effect(null);
		set_active_reaction(null);
		set_component_context(null);
		if (deactivate_batch) current_batch?.deactivate();
	}
	/**
	* @returns {(skip?: boolean) => void}
	*/
	function increment_pending() {
		var boundary = active_effect.b;
		var batch = current_batch;
		var blocking = boundary.is_rendered();
		boundary.update_pending_count(1, batch);
		batch.increment(blocking);
		return (skip = false) => {
			boundary.update_pending_count(-1, batch);
			batch.decrement(blocking, skip);
		};
	}
	/**
	* @template V
	* @param {() => V} fn
	* @returns {Derived<V>}
	*/
	/* @__NO_SIDE_EFFECTS__ */
	function derived(fn) {
		var flags = 2 | DIRTY;
		var parent_derived = active_reaction !== null && (active_reaction.f & 2) !== 0 ? active_reaction : null;
		if (active_effect !== null) active_effect.f |= EFFECT_PRESERVED;
		return {
			ctx: component_context,
			deps: null,
			effects: null,
			equals,
			f: flags,
			fn,
			reactions: null,
			rv: 0,
			v: UNINITIALIZED,
			wv: 0,
			parent: parent_derived ?? active_effect,
			ac: null
		};
	}
	/**
	* @template V
	* @param {() => V | Promise<V>} fn
	* @param {string} [label]
	* @param {string} [location] If provided, print a warning if the value is not read immediately after update
	* @returns {Promise<Source<V>>}
	*/
	/* @__NO_SIDE_EFFECTS__ */
	function async_derived(fn, label, location) {
		let parent = active_effect;
		if (parent === null) async_derived_orphan();
		var promise = void 0;
		var signal = source(UNINITIALIZED);
		var should_suspend = !active_reaction;
		/** @type {Map<Batch, ReturnType<typeof deferred<V>>>} */
		var deferreds = /* @__PURE__ */ new Map();
		async_effect(() => {
			var effect = active_effect;
			/** @type {ReturnType<typeof deferred<V>>} */
			var d = deferred();
			promise = d.promise;
			try {
				Promise.resolve(fn()).then(d.resolve, d.reject).finally(unset_context);
			} catch (error) {
				d.reject(error);
				unset_context();
			}
			var batch = current_batch;
			if (should_suspend) {
				if ((effect.f & 32768) !== 0) var decrement_pending = increment_pending();
				if (parent.b.is_rendered()) {
					deferreds.get(batch)?.reject(STALE_REACTION);
					deferreds.delete(batch);
				} else {
					for (const d of deferreds.values()) d.reject(STALE_REACTION);
					deferreds.clear();
				}
				deferreds.set(batch, d);
			}
			/**
			* @param {any} value
			* @param {unknown} error
			*/
			const handler = (value, error = void 0) => {
				if (decrement_pending) decrement_pending(error === STALE_REACTION);
				if (error === STALE_REACTION || (effect.f & 16384) !== 0) return;
				batch.activate();
				if (error) {
					signal.f |= ERROR_VALUE;
					internal_set(signal, error);
				} else {
					if ((signal.f & 8388608) !== 0) signal.f ^= ERROR_VALUE;
					internal_set(signal, value);
					for (const [b, d] of deferreds) {
						deferreds.delete(b);
						if (b === batch) break;
						d.reject(STALE_REACTION);
					}
				}
				batch.deactivate();
			};
			d.promise.then(handler, (e) => handler(null, e || "unknown"));
		});
		teardown(() => {
			for (const d of deferreds.values()) d.reject(STALE_REACTION);
		});
		return new Promise((fulfil) => {
			/** @param {Promise<V>} p */
			function next(p) {
				function go() {
					if (p === promise) fulfil(signal);
					else next(promise);
				}
				p.then(go, go);
			}
			next(promise);
		});
	}
	/**
	* @template V
	* @param {() => V} fn
	* @returns {Derived<V>}
	*/
	/* @__NO_SIDE_EFFECTS__ */
	function user_derived(fn) {
		const d = /* @__PURE__ */ derived(fn);
		if (!async_mode_flag) push_reaction_value(d);
		return d;
	}
	/**
	* @template V
	* @param {() => V} fn
	* @returns {Derived<V>}
	*/
	/* @__NO_SIDE_EFFECTS__ */
	function derived_safe_equal(fn) {
		const signal = /* @__PURE__ */ derived(fn);
		signal.equals = safe_equals;
		return signal;
	}
	/**
	* @param {Derived} derived
	* @returns {void}
	*/
	function destroy_derived_effects(derived) {
		var effects = derived.effects;
		if (effects !== null) {
			derived.effects = null;
			for (var i = 0; i < effects.length; i += 1) destroy_effect(effects[i]);
		}
	}
	/**
	* @param {Derived} derived
	* @returns {Effect | null}
	*/
	function get_derived_parent_effect(derived) {
		var parent = derived.parent;
		while (parent !== null) {
			if ((parent.f & 2) === 0) return (parent.f & 16384) === 0 ? parent : null;
			parent = parent.parent;
		}
		return null;
	}
	/**
	* @template T
	* @param {Derived} derived
	* @returns {T}
	*/
	function execute_derived(derived) {
		var value;
		var prev_active_effect = active_effect;
		set_active_effect(get_derived_parent_effect(derived));
		try {
			derived.f &= ~WAS_MARKED;
			destroy_derived_effects(derived);
			value = update_reaction(derived);
		} finally {
			set_active_effect(prev_active_effect);
		}
		return value;
	}
	/**
	* @param {Derived} derived
	* @returns {void}
	*/
	function update_derived(derived) {
		var old_value = derived.v;
		var value = execute_derived(derived);
		if (!derived.equals(value)) {
			derived.wv = increment_write_version();
			if (!current_batch?.is_fork || derived.deps === null) {
				derived.v = value;
				current_batch?.capture(derived, old_value);
				if (derived.deps === null) {
					set_signal_status(derived, CLEAN);
					return;
				}
			}
		}
		if (is_destroying_effect) return;
		if (batch_values !== null) {
			if (effect_tracking() || current_batch?.is_fork) batch_values.set(derived, value);
		} else update_derived_status(derived);
	}
	/**
	* @param {Derived} derived
	*/
	function freeze_derived_effects(derived) {
		if (derived.effects === null) return;
		for (const e of derived.effects) if (e.teardown || e.ac) {
			e.teardown?.();
			e.ac?.abort(STALE_REACTION);
			e.teardown = noop;
			e.ac = null;
			remove_reactions(e, 0);
			destroy_effect_children(e);
		}
	}
	/**
	* @param {Derived} derived
	*/
	function unfreeze_derived_effects(derived) {
		if (derived.effects === null) return;
		for (const e of derived.effects) if (e.teardown) update_effect(e);
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/reactivity/sources.js
	/** @import { Derived, Effect, Source, Value } from '#client' */
	/** @type {Set<any>} */
	var eager_effects = /* @__PURE__ */ new Set();
	/** @type {Map<Source, any>} */
	var old_values = /* @__PURE__ */ new Map();
	var eager_effects_deferred = false;
	/**
	* @template V
	* @param {V} v
	* @param {Error | null} [stack]
	* @returns {Source<V>}
	*/
	function source(v, stack) {
		return {
			f: 0,
			v,
			reactions: null,
			equals,
			rv: 0,
			wv: 0
		};
	}
	/**
	* @template V
	* @param {V} v
	* @param {Error | null} [stack]
	*/
	/* @__NO_SIDE_EFFECTS__ */
	function state(v, stack) {
		const s = source(v, stack);
		push_reaction_value(s);
		return s;
	}
	/**
	* @template V
	* @param {V} initial_value
	* @param {boolean} [immutable]
	* @returns {Source<V>}
	*/
	/* @__NO_SIDE_EFFECTS__ */
	function mutable_source(initial_value, immutable = false, trackable = true) {
		const s = source(initial_value);
		if (!immutable) s.equals = safe_equals;
		if (legacy_mode_flag && trackable && component_context !== null && component_context.l !== null) (component_context.l.s ??= []).push(s);
		return s;
	}
	/**
	* @template V
	* @param {Source<V>} source
	* @param {V} value
	* @param {boolean} [should_proxy]
	* @returns {V}
	*/
	function set(source, value, should_proxy = false) {
		if (active_reaction !== null && (!untracking || (active_reaction.f & 131072) !== 0) && is_runes() && (active_reaction.f & 4325394) !== 0 && (current_sources === null || !includes.call(current_sources, source))) state_unsafe_mutation();
		return internal_set(source, should_proxy ? proxy(value) : value, legacy_updates);
	}
	/**
	* @template V
	* @param {Source<V>} source
	* @param {V} value
	* @param {Effect[] | null} [updated_during_traversal]
	* @returns {V}
	*/
	function internal_set(source, value, updated_during_traversal = null) {
		if (!source.equals(value)) {
			var old_value = source.v;
			if (is_destroying_effect) old_values.set(source, value);
			else old_values.set(source, old_value);
			source.v = value;
			var batch = Batch.ensure();
			batch.capture(source, old_value);
			if ((source.f & 2) !== 0) {
				const derived = source;
				if ((source.f & 2048) !== 0) execute_derived(derived);
				if (batch_values === null) update_derived_status(derived);
			}
			source.wv = increment_write_version();
			mark_reactions(source, DIRTY, updated_during_traversal);
			if (is_runes() && active_effect !== null && (active_effect.f & 1024) !== 0 && (active_effect.f & 96) === 0) if (untracked_writes === null) set_untracked_writes([source]);
			else untracked_writes.push(source);
			if (!batch.is_fork && eager_effects.size > 0 && !eager_effects_deferred) flush_eager_effects();
		}
		return value;
	}
	function flush_eager_effects() {
		eager_effects_deferred = false;
		for (const effect of eager_effects) {
			if ((effect.f & 1024) !== 0) set_signal_status(effect, MAYBE_DIRTY);
			if (is_dirty(effect)) update_effect(effect);
		}
		eager_effects.clear();
	}
	/**
	* Silently (without using `get`) increment a source
	* @param {Source<number>} source
	*/
	function increment(source) {
		set(source, source.v + 1);
	}
	/**
	* @param {Value} signal
	* @param {number} status should be DIRTY or MAYBE_DIRTY
	* @param {Effect[] | null} updated_during_traversal
	* @returns {void}
	*/
	function mark_reactions(signal, status, updated_during_traversal) {
		var reactions = signal.reactions;
		if (reactions === null) return;
		var runes = is_runes();
		var length = reactions.length;
		for (var i = 0; i < length; i++) {
			var reaction = reactions[i];
			var flags = reaction.f;
			if (!runes && reaction === active_effect) continue;
			var not_dirty = (flags & DIRTY) === 0;
			if (not_dirty) set_signal_status(reaction, status);
			if ((flags & 2) !== 0) {
				var derived = reaction;
				batch_values?.delete(derived);
				if ((flags & 65536) === 0) {
					if (flags & 512) reaction.f |= WAS_MARKED;
					mark_reactions(derived, MAYBE_DIRTY, updated_during_traversal);
				}
			} else if (not_dirty) {
				var effect = reaction;
				if ((flags & 16) !== 0 && eager_block_effects !== null) eager_block_effects.add(effect);
				if (updated_during_traversal !== null) updated_during_traversal.push(effect);
				else schedule_effect(effect);
			}
		}
	}
	/**
	* @template T
	* @param {T} value
	* @returns {T}
	*/
	function proxy(value) {
		if (typeof value !== "object" || value === null || STATE_SYMBOL in value) return value;
		const prototype = get_prototype_of(value);
		if (prototype !== object_prototype && prototype !== array_prototype) return value;
		/** @type {Map<any, Source<any>>} */
		var sources = /* @__PURE__ */ new Map();
		var is_proxied_array = is_array(value);
		var version = /* @__PURE__ */ state(0);
		var stack = null;
		var parent_version = update_version;
		/**
		* Executes the proxy in the context of the reaction it was originally created in, if any
		* @template T
		* @param {() => T} fn
		*/
		var with_parent = (fn) => {
			if (update_version === parent_version) return fn();
			var reaction = active_reaction;
			var version = update_version;
			set_active_reaction(null);
			set_update_version(parent_version);
			var result = fn();
			set_active_reaction(reaction);
			set_update_version(version);
			return result;
		};
		if (is_proxied_array) sources.set("length", /* @__PURE__ */ state(
			/** @type {any[]} */
			value.length,
			stack
		));
		return new Proxy(value, {
			defineProperty(_, prop, descriptor) {
				if (!("value" in descriptor) || descriptor.configurable === false || descriptor.enumerable === false || descriptor.writable === false) state_descriptors_fixed();
				var s = sources.get(prop);
				if (s === void 0) with_parent(() => {
					var s = /* @__PURE__ */ state(descriptor.value, stack);
					sources.set(prop, s);
					return s;
				});
				else set(s, descriptor.value, true);
				return true;
			},
			deleteProperty(target, prop) {
				var s = sources.get(prop);
				if (s === void 0) {
					if (prop in target) {
						const s = with_parent(() => /* @__PURE__ */ state(UNINITIALIZED, stack));
						sources.set(prop, s);
						increment(version);
					}
				} else {
					set(s, UNINITIALIZED);
					increment(version);
				}
				return true;
			},
			get(target, prop, receiver) {
				if (prop === STATE_SYMBOL) return value;
				var s = sources.get(prop);
				var exists = prop in target;
				if (s === void 0 && (!exists || get_descriptor(target, prop)?.writable)) {
					s = with_parent(() => {
						return /* @__PURE__ */ state(proxy(exists ? target[prop] : UNINITIALIZED), stack);
					});
					sources.set(prop, s);
				}
				if (s !== void 0) {
					var v = get(s);
					return v === UNINITIALIZED ? void 0 : v;
				}
				return Reflect.get(target, prop, receiver);
			},
			getOwnPropertyDescriptor(target, prop) {
				var descriptor = Reflect.getOwnPropertyDescriptor(target, prop);
				if (descriptor && "value" in descriptor) {
					var s = sources.get(prop);
					if (s) descriptor.value = get(s);
				} else if (descriptor === void 0) {
					var source = sources.get(prop);
					var value = source?.v;
					if (source !== void 0 && value !== UNINITIALIZED) return {
						enumerable: true,
						configurable: true,
						value,
						writable: true
					};
				}
				return descriptor;
			},
			has(target, prop) {
				if (prop === STATE_SYMBOL) return true;
				var s = sources.get(prop);
				var has = s !== void 0 && s.v !== UNINITIALIZED || Reflect.has(target, prop);
				if (s !== void 0 || active_effect !== null && (!has || get_descriptor(target, prop)?.writable)) {
					if (s === void 0) {
						s = with_parent(() => {
							return /* @__PURE__ */ state(has ? proxy(target[prop]) : UNINITIALIZED, stack);
						});
						sources.set(prop, s);
					}
					if (get(s) === UNINITIALIZED) return false;
				}
				return has;
			},
			set(target, prop, value, receiver) {
				var s = sources.get(prop);
				var has = prop in target;
				if (is_proxied_array && prop === "length") for (var i = value; i < s.v; i += 1) {
					var other_s = sources.get(i + "");
					if (other_s !== void 0) set(other_s, UNINITIALIZED);
					else if (i in target) {
						other_s = with_parent(() => /* @__PURE__ */ state(UNINITIALIZED, stack));
						sources.set(i + "", other_s);
					}
				}
				if (s === void 0) {
					if (!has || get_descriptor(target, prop)?.writable) {
						s = with_parent(() => /* @__PURE__ */ state(void 0, stack));
						set(s, proxy(value));
						sources.set(prop, s);
					}
				} else {
					has = s.v !== UNINITIALIZED;
					var p = with_parent(() => proxy(value));
					set(s, p);
				}
				var descriptor = Reflect.getOwnPropertyDescriptor(target, prop);
				if (descriptor?.set) descriptor.set.call(receiver, value);
				if (!has) {
					if (is_proxied_array && typeof prop === "string") {
						var ls = sources.get("length");
						var n = Number(prop);
						if (Number.isInteger(n) && n >= ls.v) set(ls, n + 1);
					}
					increment(version);
				}
				return true;
			},
			ownKeys(target) {
				get(version);
				var own_keys = Reflect.ownKeys(target).filter((key) => {
					var source = sources.get(key);
					return source === void 0 || source.v !== UNINITIALIZED;
				});
				for (var [key, source] of sources) if (source.v !== UNINITIALIZED && !(key in target)) own_keys.push(key);
				return own_keys;
			},
			setPrototypeOf() {
				state_prototype_fixed();
			}
		});
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/dom/operations.js
	/** @import { Effect, TemplateNode } from '#client' */
	/** @type {Window} */
	var $window;
	/** @type {boolean} */
	var is_firefox;
	/** @type {() => Node | null} */
	var first_child_getter;
	/** @type {() => Node | null} */
	var next_sibling_getter;
	/**
	* Initialize these lazily to avoid issues when using the runtime in a server context
	* where these globals are not available while avoiding a separate server entry point
	*/
	function init_operations() {
		if ($window !== void 0) return;
		$window = window;
		is_firefox = /Firefox/.test(navigator.userAgent);
		var element_prototype = Element.prototype;
		var node_prototype = Node.prototype;
		var text_prototype = Text.prototype;
		first_child_getter = get_descriptor(node_prototype, "firstChild").get;
		next_sibling_getter = get_descriptor(node_prototype, "nextSibling").get;
		if (is_extensible(element_prototype)) {
			element_prototype.__click = void 0;
			element_prototype.__className = void 0;
			element_prototype.__attributes = null;
			element_prototype.__style = void 0;
			element_prototype.__e = void 0;
		}
		if (is_extensible(text_prototype)) text_prototype.__t = void 0;
	}
	/**
	* @param {string} value
	* @returns {Text}
	*/
	function create_text(value = "") {
		return document.createTextNode(value);
	}
	/**
	* @template {Node} N
	* @param {N} node
	*/
	/* @__NO_SIDE_EFFECTS__ */
	function get_first_child(node) {
		return first_child_getter.call(node);
	}
	/**
	* @template {Node} N
	* @param {N} node
	*/
	/* @__NO_SIDE_EFFECTS__ */
	function get_next_sibling(node) {
		return next_sibling_getter.call(node);
	}
	/**
	* Don't mark this as side-effect-free, hydration needs to walk all nodes
	* @template {Node} N
	* @param {N} node
	* @param {boolean} is_text
	* @returns {TemplateNode | null}
	*/
	function child(node, is_text) {
		if (!hydrating) return /* @__PURE__ */ get_first_child(node);
		var child = /* @__PURE__ */ get_first_child(hydrate_node);
		if (child === null) child = hydrate_node.appendChild(create_text());
		else if (is_text && child.nodeType !== 3) {
			var text = create_text();
			child?.before(text);
			set_hydrate_node(text);
			return text;
		}
		if (is_text) merge_text_nodes(child);
		set_hydrate_node(child);
		return child;
	}
	/**
	* Don't mark this as side-effect-free, hydration needs to walk all nodes
	* @param {TemplateNode} node
	* @param {boolean} [is_text]
	* @returns {TemplateNode | null}
	*/
	function first_child(node, is_text = false) {
		if (!hydrating) {
			var first = /* @__PURE__ */ get_first_child(node);
			if (first instanceof Comment && first.data === "") return /* @__PURE__ */ get_next_sibling(first);
			return first;
		}
		if (is_text) {
			if (hydrate_node?.nodeType !== 3) {
				var text = create_text();
				hydrate_node?.before(text);
				set_hydrate_node(text);
				return text;
			}
			merge_text_nodes(hydrate_node);
		}
		return hydrate_node;
	}
	/**
	* Don't mark this as side-effect-free, hydration needs to walk all nodes
	* @param {TemplateNode} node
	* @param {number} count
	* @param {boolean} is_text
	* @returns {TemplateNode | null}
	*/
	function sibling(node, count = 1, is_text = false) {
		let next_sibling = hydrating ? hydrate_node : node;
		var last_sibling;
		while (count--) {
			last_sibling = next_sibling;
			next_sibling = /* @__PURE__ */ get_next_sibling(next_sibling);
		}
		if (!hydrating) return next_sibling;
		if (is_text) {
			if (next_sibling?.nodeType !== 3) {
				var text = create_text();
				if (next_sibling === null) last_sibling?.after(text);
				else next_sibling.before(text);
				set_hydrate_node(text);
				return text;
			}
			merge_text_nodes(next_sibling);
		}
		set_hydrate_node(next_sibling);
		return next_sibling;
	}
	/**
	* @template {Node} N
	* @param {N} node
	* @returns {void}
	*/
	function clear_text_content(node) {
		node.textContent = "";
	}
	/**
	* Returns `true` if we're updating the current block, for example `condition` in
	* an `{#if condition}` block just changed. In this case, the branch should be
	* appended (or removed) at the same time as other updates within the
	* current `<svelte:boundary>`
	*/
	function should_defer_append() {
		if (!async_mode_flag) return false;
		if (eager_block_effects !== null) return false;
		return (active_effect.f & REACTION_RAN) !== 0;
	}
	/**
	* @template {keyof HTMLElementTagNameMap | string} T
	* @param {T} tag
	* @param {string} [namespace]
	* @param {string} [is]
	* @returns {T extends keyof HTMLElementTagNameMap ? HTMLElementTagNameMap[T] : Element}
	*/
	function create_element(tag, namespace, is) {
		let options = is ? { is } : void 0;
		return document.createElementNS(namespace ?? "http://www.w3.org/1999/xhtml", tag, options);
	}
	/**
	* Browsers split text nodes larger than 65536 bytes when parsing.
	* For hydration to succeed, we need to stitch them back together
	* @param {Text} text
	*/
	function merge_text_nodes(text) {
		if (text.nodeValue.length < 65536) return;
		let next = text.nextSibling;
		while (next !== null && next.nodeType === 3) {
			next.remove();
			/** @type {string} */ text.nodeValue += next.nodeValue;
			next = text.nextSibling;
		}
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/dom/elements/misc.js
	/**
	* The child of a textarea actually corresponds to the defaultValue property, so we need
	* to remove it upon hydration to avoid a bug when someone resets the form value.
	* @param {HTMLTextAreaElement} dom
	* @returns {void}
	*/
	function remove_textarea_child(dom) {
		if (hydrating && /* @__PURE__ */ get_first_child(dom) !== null) clear_text_content(dom);
	}
	var listening_to_form_reset = false;
	function add_form_reset_listener() {
		if (!listening_to_form_reset) {
			listening_to_form_reset = true;
			document.addEventListener("reset", (evt) => {
				Promise.resolve().then(() => {
					if (!evt.defaultPrevented) for (const e of evt.target.elements) e.__on_r?.();
				});
			}, { capture: true });
		}
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/dom/elements/bindings/shared.js
	/**
	* @template T
	* @param {() => T} fn
	*/
	function without_reactive_context(fn) {
		var previous_reaction = active_reaction;
		var previous_effect = active_effect;
		set_active_reaction(null);
		set_active_effect(null);
		try {
			return fn();
		} finally {
			set_active_reaction(previous_reaction);
			set_active_effect(previous_effect);
		}
	}
	/**
	* Listen to the given event, and then instantiate a global form reset listener if not already done,
	* to notify all bindings when the form is reset
	* @param {HTMLElement} element
	* @param {string} event
	* @param {(is_reset?: true) => void} handler
	* @param {(is_reset?: true) => void} [on_reset]
	*/
	function listen_to_event_and_reset_event(element, event, handler, on_reset = handler) {
		element.addEventListener(event, () => without_reactive_context(handler));
		const prev = element.__on_r;
		if (prev) element.__on_r = () => {
			prev();
			on_reset(true);
		};
		else element.__on_r = () => on_reset(true);
		add_form_reset_listener();
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/reactivity/effects.js
	/** @import { Blocker, ComponentContext, ComponentContextLegacy, Derived, Effect, TemplateNode, TransitionManager } from '#client' */
	/**
	* @param {'$effect' | '$effect.pre' | '$inspect'} rune
	*/
	function validate_effect(rune) {
		if (active_effect === null) {
			if (active_reaction === null) effect_orphan(rune);
			effect_in_unowned_derived();
		}
		if (is_destroying_effect) effect_in_teardown(rune);
	}
	/**
	* @param {Effect} effect
	* @param {Effect} parent_effect
	*/
	function push_effect(effect, parent_effect) {
		var parent_last = parent_effect.last;
		if (parent_last === null) parent_effect.last = parent_effect.first = effect;
		else {
			parent_last.next = effect;
			effect.prev = parent_last;
			parent_effect.last = effect;
		}
	}
	/**
	* @param {number} type
	* @param {null | (() => void | (() => void))} fn
	* @returns {Effect}
	*/
	function create_effect(type, fn) {
		var parent = active_effect;
		if (parent !== null && (parent.f & 8192) !== 0) type |= INERT;
		/** @type {Effect} */
		var effect = {
			ctx: component_context,
			deps: null,
			nodes: null,
			f: type | DIRTY | 512,
			first: null,
			fn,
			last: null,
			next: null,
			parent,
			b: parent && parent.b,
			prev: null,
			teardown: null,
			wv: 0,
			ac: null
		};
		/** @type {Effect | null} */
		var e = effect;
		if ((type & 4) !== 0) if (collected_effects !== null) collected_effects.push(effect);
		else Batch.ensure().schedule(effect);
		else if (fn !== null) {
			try {
				update_effect(effect);
			} catch (e) {
				destroy_effect(effect);
				throw e;
			}
			if (e.deps === null && e.teardown === null && e.nodes === null && e.first === e.last && (e.f & 524288) === 0) {
				e = e.first;
				if ((type & 16) !== 0 && (type & 65536) !== 0 && e !== null) e.f |= EFFECT_TRANSPARENT;
			}
		}
		if (e !== null) {
			e.parent = parent;
			if (parent !== null) push_effect(e, parent);
			if (active_reaction !== null && (active_reaction.f & 2) !== 0 && (type & 64) === 0) {
				var derived = active_reaction;
				(derived.effects ??= []).push(e);
			}
		}
		return effect;
	}
	/**
	* Internal representation of `$effect.tracking()`
	* @returns {boolean}
	*/
	function effect_tracking() {
		return active_reaction !== null && !untracking;
	}
	/**
	* @param {() => void} fn
	*/
	function teardown(fn) {
		const effect = create_effect(8, null);
		set_signal_status(effect, CLEAN);
		effect.teardown = fn;
		return effect;
	}
	/**
	* Internal representation of `$effect(...)`
	* @param {() => void | (() => void)} fn
	*/
	function user_effect(fn) {
		validate_effect("$effect");
		var flags = active_effect.f;
		if (!active_reaction && (flags & 32) !== 0 && (flags & 32768) === 0) {
			var context = component_context;
			(context.e ??= []).push(fn);
		} else return create_user_effect(fn);
	}
	/**
	* @param {() => void | (() => void)} fn
	*/
	function create_user_effect(fn) {
		return create_effect(4 | USER_EFFECT, fn);
	}
	/**
	* Internal representation of `$effect.root(...)`
	* @param {() => void | (() => void)} fn
	* @returns {() => void}
	*/
	function effect_root(fn) {
		Batch.ensure();
		const effect = create_effect(64 | EFFECT_PRESERVED, fn);
		return () => {
			destroy_effect(effect);
		};
	}
	/**
	* An effect root whose children can transition out
	* @param {() => void} fn
	* @returns {(options?: { outro?: boolean }) => Promise<void>}
	*/
	function component_root(fn) {
		Batch.ensure();
		const effect = create_effect(64 | EFFECT_PRESERVED, fn);
		return (options = {}) => {
			return new Promise((fulfil) => {
				if (options.outro) pause_effect(effect, () => {
					destroy_effect(effect);
					fulfil(void 0);
				});
				else {
					destroy_effect(effect);
					fulfil(void 0);
				}
			});
		};
	}
	/**
	* @param {() => void | (() => void)} fn
	* @returns {Effect}
	*/
	function effect(fn) {
		return create_effect(4, fn);
	}
	/**
	* @param {() => void | (() => void)} fn
	* @returns {Effect}
	*/
	function async_effect(fn) {
		return create_effect(ASYNC | EFFECT_PRESERVED, fn);
	}
	/**
	* @param {() => void | (() => void)} fn
	* @returns {Effect}
	*/
	function render_effect(fn, flags = 0) {
		return create_effect(8 | flags, fn);
	}
	/**
	* @param {(...expressions: any) => void | (() => void)} fn
	* @param {Array<() => any>} sync
	* @param {Array<() => Promise<any>>} async
	* @param {Blocker[]} blockers
	*/
	function template_effect(fn, sync = [], async = [], blockers = []) {
		flatten(blockers, sync, async, (values) => {
			create_effect(8, () => fn(...values.map(get)));
		});
	}
	/**
	* @param {(() => void)} fn
	* @param {number} flags
	*/
	function block(fn, flags = 0) {
		return create_effect(16 | flags, fn);
	}
	/**
	* @param {(() => void)} fn
	*/
	function branch(fn) {
		return create_effect(32 | EFFECT_PRESERVED, fn);
	}
	/**
	* @param {Effect} effect
	*/
	function execute_effect_teardown(effect) {
		var teardown = effect.teardown;
		if (teardown !== null) {
			const previously_destroying_effect = is_destroying_effect;
			const previous_reaction = active_reaction;
			set_is_destroying_effect(true);
			set_active_reaction(null);
			try {
				teardown.call(null);
			} finally {
				set_is_destroying_effect(previously_destroying_effect);
				set_active_reaction(previous_reaction);
			}
		}
	}
	/**
	* @param {Effect} signal
	* @param {boolean} remove_dom
	* @returns {void}
	*/
	function destroy_effect_children(signal, remove_dom = false) {
		var effect = signal.first;
		signal.first = signal.last = null;
		while (effect !== null) {
			const controller = effect.ac;
			if (controller !== null) without_reactive_context(() => {
				controller.abort(STALE_REACTION);
			});
			var next = effect.next;
			if ((effect.f & 64) !== 0) effect.parent = null;
			else destroy_effect(effect, remove_dom);
			effect = next;
		}
	}
	/**
	* @param {Effect} signal
	* @returns {void}
	*/
	function destroy_block_effect_children(signal) {
		var effect = signal.first;
		while (effect !== null) {
			var next = effect.next;
			if ((effect.f & 32) === 0) destroy_effect(effect);
			effect = next;
		}
	}
	/**
	* @param {Effect} effect
	* @param {boolean} [remove_dom]
	* @returns {void}
	*/
	function destroy_effect(effect, remove_dom = true) {
		var removed = false;
		if ((remove_dom || (effect.f & 262144) !== 0) && effect.nodes !== null && effect.nodes.end !== null) {
			remove_effect_dom(effect.nodes.start, effect.nodes.end);
			removed = true;
		}
		set_signal_status(effect, DESTROYING);
		destroy_effect_children(effect, remove_dom && !removed);
		remove_reactions(effect, 0);
		var transitions = effect.nodes && effect.nodes.t;
		if (transitions !== null) for (const transition of transitions) transition.stop();
		execute_effect_teardown(effect);
		effect.f ^= DESTROYING;
		effect.f |= DESTROYED;
		var parent = effect.parent;
		if (parent !== null && parent.first !== null) unlink_effect(effect);
		effect.next = effect.prev = effect.teardown = effect.ctx = effect.deps = effect.fn = effect.nodes = effect.ac = null;
	}
	/**
	*
	* @param {TemplateNode | null} node
	* @param {TemplateNode} end
	*/
	function remove_effect_dom(node, end) {
		while (node !== null) {
			/** @type {TemplateNode | null} */
			var next = node === end ? null : /* @__PURE__ */ get_next_sibling(node);
			node.remove();
			node = next;
		}
	}
	/**
	* Detach an effect from the effect tree, freeing up memory and
	* reducing the amount of work that happens on subsequent traversals
	* @param {Effect} effect
	*/
	function unlink_effect(effect) {
		var parent = effect.parent;
		var prev = effect.prev;
		var next = effect.next;
		if (prev !== null) prev.next = next;
		if (next !== null) next.prev = prev;
		if (parent !== null) {
			if (parent.first === effect) parent.first = next;
			if (parent.last === effect) parent.last = prev;
		}
	}
	/**
	* When a block effect is removed, we don't immediately destroy it or yank it
	* out of the DOM, because it might have transitions. Instead, we 'pause' it.
	* It stays around (in memory, and in the DOM) until outro transitions have
	* completed, and if the state change is reversed then we _resume_ it.
	* A paused effect does not update, and the DOM subtree becomes inert.
	* @param {Effect} effect
	* @param {() => void} [callback]
	* @param {boolean} [destroy]
	*/
	function pause_effect(effect, callback, destroy = true) {
		/** @type {TransitionManager[]} */
		var transitions = [];
		pause_children(effect, transitions, true);
		var fn = () => {
			if (destroy) destroy_effect(effect);
			if (callback) callback();
		};
		var remaining = transitions.length;
		if (remaining > 0) {
			var check = () => --remaining || fn();
			for (var transition of transitions) transition.out(check);
		} else fn();
	}
	/**
	* @param {Effect} effect
	* @param {TransitionManager[]} transitions
	* @param {boolean} local
	*/
	function pause_children(effect, transitions, local) {
		if ((effect.f & 8192) !== 0) return;
		effect.f ^= INERT;
		var t = effect.nodes && effect.nodes.t;
		if (t !== null) {
			for (const transition of t) if (transition.is_global || local) transitions.push(transition);
		}
		var child = effect.first;
		while (child !== null) {
			var sibling = child.next;
			var transparent = (child.f & 65536) !== 0 || (child.f & 32) !== 0 && (effect.f & 16) !== 0;
			pause_children(child, transitions, transparent ? local : false);
			child = sibling;
		}
	}
	/**
	* The opposite of `pause_effect`. We call this if (for example)
	* `x` becomes falsy then truthy: `{#if x}...{/if}`
	* @param {Effect} effect
	*/
	function resume_effect(effect) {
		resume_children(effect, true);
	}
	/**
	* @param {Effect} effect
	* @param {boolean} local
	*/
	function resume_children(effect, local) {
		if ((effect.f & 8192) === 0) return;
		effect.f ^= INERT;
		if ((effect.f & 1024) === 0) {
			set_signal_status(effect, DIRTY);
			Batch.ensure().schedule(effect);
		}
		var child = effect.first;
		while (child !== null) {
			var sibling = child.next;
			var transparent = (child.f & 65536) !== 0 || (child.f & 32) !== 0;
			resume_children(child, transparent ? local : false);
			child = sibling;
		}
		var t = effect.nodes && effect.nodes.t;
		if (t !== null) {
			for (const transition of t) if (transition.is_global || local) transition.in();
		}
	}
	/**
	* @param {Effect} effect
	* @param {DocumentFragment} fragment
	*/
	function move_effect(effect, fragment) {
		if (!effect.nodes) return;
		/** @type {TemplateNode | null} */
		var node = effect.nodes.start;
		var end = effect.nodes.end;
		while (node !== null) {
			/** @type {TemplateNode | null} */
			var next = node === end ? null : /* @__PURE__ */ get_next_sibling(node);
			fragment.append(node);
			node = next;
		}
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/legacy.js
	/**
	* @type {Set<Value> | null}
	* @deprecated
	*/
	var captured_signals = null;
	//#endregion
	//#region node_modules/svelte/src/internal/client/runtime.js
	/** @import { Derived, Effect, Reaction, Source, Value } from '#client' */
	var is_updating_effect = false;
	var is_destroying_effect = false;
	/** @param {boolean} value */
	function set_is_destroying_effect(value) {
		is_destroying_effect = value;
	}
	/** @type {null | Reaction} */
	var active_reaction = null;
	var untracking = false;
	/** @param {null | Reaction} reaction */
	function set_active_reaction(reaction) {
		active_reaction = reaction;
	}
	/** @type {null | Effect} */
	var active_effect = null;
	/** @param {null | Effect} effect */
	function set_active_effect(effect) {
		active_effect = effect;
	}
	/**
	* When sources are created within a reaction, reading and writing
	* them within that reaction should not cause a re-run
	* @type {null | Source[]}
	*/
	var current_sources = null;
	/** @param {Value} value */
	function push_reaction_value(value) {
		if (active_reaction !== null && (!async_mode_flag || (active_reaction.f & 2) !== 0)) if (current_sources === null) current_sources = [value];
		else current_sources.push(value);
	}
	/**
	* The dependencies of the reaction that is currently being executed. In many cases,
	* the dependencies are unchanged between runs, and so this will be `null` unless
	* and until a new dependency is accessed — we track this via `skipped_deps`
	* @type {null | Value[]}
	*/
	var new_deps = null;
	var skipped_deps = 0;
	/**
	* Tracks writes that the effect it's executed in doesn't listen to yet,
	* so that the dependency can be added to the effect later on if it then reads it
	* @type {null | Source[]}
	*/
	var untracked_writes = null;
	/** @param {null | Source[]} value */
	function set_untracked_writes(value) {
		untracked_writes = value;
	}
	/**
	* @type {number} Used by sources and deriveds for handling updates.
	* Version starts from 1 so that unowned deriveds differentiate between a created effect and a run one for tracing
	**/
	var write_version = 1;
	/** @type {number} Used to version each read of a source of derived to avoid duplicating depedencies inside a reaction */
	var read_version = 0;
	var update_version = read_version;
	/** @param {number} value */
	function set_update_version(value) {
		update_version = value;
	}
	function increment_write_version() {
		return ++write_version;
	}
	/**
	* Determines whether a derived or effect is dirty.
	* If it is MAYBE_DIRTY, will set the status to CLEAN
	* @param {Reaction} reaction
	* @returns {boolean}
	*/
	function is_dirty(reaction) {
		var flags = reaction.f;
		if ((flags & 2048) !== 0) return true;
		if (flags & 2) reaction.f &= ~WAS_MARKED;
		if ((flags & 4096) !== 0) {
			var dependencies = reaction.deps;
			var length = dependencies.length;
			for (var i = 0; i < length; i++) {
				var dependency = dependencies[i];
				if (is_dirty(dependency)) update_derived(dependency);
				if (dependency.wv > reaction.wv) return true;
			}
			if ((flags & 512) !== 0 && batch_values === null) set_signal_status(reaction, CLEAN);
		}
		return false;
	}
	/**
	* @param {Value} signal
	* @param {Effect} effect
	* @param {boolean} [root]
	*/
	function schedule_possible_effect_self_invalidation(signal, effect, root = true) {
		var reactions = signal.reactions;
		if (reactions === null) return;
		if (!async_mode_flag && current_sources !== null && includes.call(current_sources, signal)) return;
		for (var i = 0; i < reactions.length; i++) {
			var reaction = reactions[i];
			if ((reaction.f & 2) !== 0) schedule_possible_effect_self_invalidation(reaction, effect, false);
			else if (effect === reaction) {
				if (root) set_signal_status(reaction, DIRTY);
				else if ((reaction.f & 1024) !== 0) set_signal_status(reaction, MAYBE_DIRTY);
				schedule_effect(reaction);
			}
		}
	}
	/** @param {Reaction} reaction */
	function update_reaction(reaction) {
		var previous_deps = new_deps;
		var previous_skipped_deps = skipped_deps;
		var previous_untracked_writes = untracked_writes;
		var previous_reaction = active_reaction;
		var previous_sources = current_sources;
		var previous_component_context = component_context;
		var previous_untracking = untracking;
		var previous_update_version = update_version;
		var flags = reaction.f;
		new_deps = null;
		skipped_deps = 0;
		untracked_writes = null;
		active_reaction = (flags & 96) === 0 ? reaction : null;
		current_sources = null;
		set_component_context(reaction.ctx);
		untracking = false;
		update_version = ++read_version;
		if (reaction.ac !== null) {
			without_reactive_context(() => {
				/** @type {AbortController} */ reaction.ac.abort(STALE_REACTION);
			});
			reaction.ac = null;
		}
		try {
			reaction.f |= REACTION_IS_UPDATING;
			var fn = reaction.fn;
			var result = fn();
			reaction.f |= REACTION_RAN;
			var deps = reaction.deps;
			var is_fork = current_batch?.is_fork;
			if (new_deps !== null) {
				var i;
				if (!is_fork) remove_reactions(reaction, skipped_deps);
				if (deps !== null && skipped_deps > 0) {
					deps.length = skipped_deps + new_deps.length;
					for (i = 0; i < new_deps.length; i++) deps[skipped_deps + i] = new_deps[i];
				} else reaction.deps = deps = new_deps;
				if (effect_tracking() && (reaction.f & 512) !== 0) for (i = skipped_deps; i < deps.length; i++) (deps[i].reactions ??= []).push(reaction);
			} else if (!is_fork && deps !== null && skipped_deps < deps.length) {
				remove_reactions(reaction, skipped_deps);
				deps.length = skipped_deps;
			}
			if (is_runes() && untracked_writes !== null && !untracking && deps !== null && (reaction.f & 6146) === 0) for (i = 0; i < untracked_writes.length; i++) schedule_possible_effect_self_invalidation(untracked_writes[i], reaction);
			if (previous_reaction !== null && previous_reaction !== reaction) {
				read_version++;
				if (previous_reaction.deps !== null) for (let i = 0; i < previous_skipped_deps; i += 1) previous_reaction.deps[i].rv = read_version;
				if (previous_deps !== null) for (const dep of previous_deps) dep.rv = read_version;
				if (untracked_writes !== null) if (previous_untracked_writes === null) previous_untracked_writes = untracked_writes;
				else previous_untracked_writes.push(...untracked_writes);
			}
			if ((reaction.f & 8388608) !== 0) reaction.f ^= ERROR_VALUE;
			return result;
		} catch (error) {
			return handle_error(error);
		} finally {
			reaction.f ^= REACTION_IS_UPDATING;
			new_deps = previous_deps;
			skipped_deps = previous_skipped_deps;
			untracked_writes = previous_untracked_writes;
			active_reaction = previous_reaction;
			current_sources = previous_sources;
			set_component_context(previous_component_context);
			untracking = previous_untracking;
			update_version = previous_update_version;
		}
	}
	/**
	* @template V
	* @param {Reaction} signal
	* @param {Value<V>} dependency
	* @returns {void}
	*/
	function remove_reaction(signal, dependency) {
		let reactions = dependency.reactions;
		if (reactions !== null) {
			var index = index_of.call(reactions, signal);
			if (index !== -1) {
				var new_length = reactions.length - 1;
				if (new_length === 0) reactions = dependency.reactions = null;
				else {
					reactions[index] = reactions[new_length];
					reactions.pop();
				}
			}
		}
		if (reactions === null && (dependency.f & 2) !== 0 && (new_deps === null || !includes.call(new_deps, dependency))) {
			var derived = dependency;
			if ((derived.f & 512) !== 0) {
				derived.f ^= 512;
				derived.f &= ~WAS_MARKED;
			}
			update_derived_status(derived);
			freeze_derived_effects(derived);
			remove_reactions(derived, 0);
		}
	}
	/**
	* @param {Reaction} signal
	* @param {number} start_index
	* @returns {void}
	*/
	function remove_reactions(signal, start_index) {
		var dependencies = signal.deps;
		if (dependencies === null) return;
		for (var i = start_index; i < dependencies.length; i++) remove_reaction(signal, dependencies[i]);
	}
	/**
	* @param {Effect} effect
	* @returns {void}
	*/
	function update_effect(effect) {
		var flags = effect.f;
		if ((flags & 16384) !== 0) return;
		set_signal_status(effect, CLEAN);
		var previous_effect = active_effect;
		var was_updating_effect = is_updating_effect;
		active_effect = effect;
		is_updating_effect = true;
		try {
			if ((flags & 16777232) !== 0) destroy_block_effect_children(effect);
			else destroy_effect_children(effect);
			execute_effect_teardown(effect);
			var teardown = update_reaction(effect);
			effect.teardown = typeof teardown === "function" ? teardown : null;
			effect.wv = write_version;
		} finally {
			is_updating_effect = was_updating_effect;
			active_effect = previous_effect;
		}
	}
	/**
	* Returns a promise that resolves once any pending state changes have been applied.
	* @returns {Promise<void>}
	*/
	async function tick() {
		if (async_mode_flag) return new Promise((f) => {
			requestAnimationFrame(() => f());
			setTimeout(() => f());
		});
		await Promise.resolve();
		flushSync();
	}
	/**
	* @template V
	* @param {Value<V>} signal
	* @returns {V}
	*/
	function get(signal) {
		var is_derived = (signal.f & 2) !== 0;
		captured_signals?.add(signal);
		if (active_reaction !== null && !untracking) {
			if (!(active_effect !== null && (active_effect.f & 16384) !== 0) && (current_sources === null || !includes.call(current_sources, signal))) {
				var deps = active_reaction.deps;
				if ((active_reaction.f & 2097152) !== 0) {
					if (signal.rv < read_version) {
						signal.rv = read_version;
						if (new_deps === null && deps !== null && deps[skipped_deps] === signal) skipped_deps++;
						else if (new_deps === null) new_deps = [signal];
						else new_deps.push(signal);
					}
				} else {
					(active_reaction.deps ??= []).push(signal);
					var reactions = signal.reactions;
					if (reactions === null) signal.reactions = [active_reaction];
					else if (!includes.call(reactions, active_reaction)) reactions.push(active_reaction);
				}
			}
		}
		if (is_destroying_effect && old_values.has(signal)) return old_values.get(signal);
		if (is_derived) {
			var derived = signal;
			if (is_destroying_effect) {
				var value = derived.v;
				if ((derived.f & 1024) === 0 && derived.reactions !== null || depends_on_old_values(derived)) value = execute_derived(derived);
				old_values.set(derived, value);
				return value;
			}
			var should_connect = (derived.f & 512) === 0 && !untracking && active_reaction !== null && (is_updating_effect || (active_reaction.f & 512) !== 0);
			var is_new = (derived.f & REACTION_RAN) === 0;
			if (is_dirty(derived)) {
				if (should_connect) derived.f |= 512;
				update_derived(derived);
			}
			if (should_connect && !is_new) {
				unfreeze_derived_effects(derived);
				reconnect(derived);
			}
		}
		if (batch_values?.has(signal)) return batch_values.get(signal);
		if ((signal.f & 8388608) !== 0) throw signal.v;
		return signal.v;
	}
	/**
	* (Re)connect a disconnected derived, so that it is notified
	* of changes in `mark_reactions`
	* @param {Derived} derived
	*/
	function reconnect(derived) {
		derived.f |= 512;
		if (derived.deps === null) return;
		for (const dep of derived.deps) {
			(dep.reactions ??= []).push(derived);
			if ((dep.f & 2) !== 0 && (dep.f & 512) === 0) {
				unfreeze_derived_effects(dep);
				reconnect(dep);
			}
		}
	}
	/** @param {Derived} derived */
	function depends_on_old_values(derived) {
		if (derived.v === UNINITIALIZED) return true;
		if (derived.deps === null) return false;
		for (const dep of derived.deps) {
			if (old_values.has(dep)) return true;
			if ((dep.f & 2) !== 0 && depends_on_old_values(dep)) return true;
		}
		return false;
	}
	/**
	* When used inside a [`$derived`](https://svelte.dev/docs/svelte/$derived) or [`$effect`](https://svelte.dev/docs/svelte/$effect),
	* any state read inside `fn` will not be treated as a dependency.
	*
	* ```ts
	* $effect(() => {
	*   // this will run when `data` changes, but not when `time` changes
	*   save(data, {
	*     timestamp: untrack(() => time)
	*   });
	* });
	* ```
	* @template T
	* @param {() => T} fn
	* @returns {T}
	*/
	function untrack(fn) {
		var previous_untracking = untracking;
		try {
			untracking = true;
			return fn();
		} finally {
			untracking = previous_untracking;
		}
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/dom/elements/events.js
	/**
	* Used on elements, as a map of event type -> event handler,
	* and on events themselves to track which element handled an event
	*/
	var event_symbol = Symbol("events");
	/** @type {Set<string>} */
	var all_registered_events = /* @__PURE__ */ new Set();
	/** @type {Set<(events: Array<string>) => void>} */
	var root_event_handles = /* @__PURE__ */ new Set();
	/**
	* @param {string} event_name
	* @param {EventTarget} dom
	* @param {EventListener} [handler]
	* @param {AddEventListenerOptions} [options]
	*/
	function create_event(event_name, dom, handler, options = {}) {
		/**
		* @this {EventTarget}
		*/
		function target_handler(event) {
			if (!options.capture) handle_event_propagation.call(dom, event);
			if (!event.cancelBubble) return without_reactive_context(() => {
				return handler?.call(this, event);
			});
		}
		if (event_name.startsWith("pointer") || event_name.startsWith("touch") || event_name === "wheel") queue_micro_task(() => {
			dom.addEventListener(event_name, target_handler, options);
		});
		else dom.addEventListener(event_name, target_handler, options);
		return target_handler;
	}
	/**
	* @param {string} event_name
	* @param {Element} dom
	* @param {EventListener} [handler]
	* @param {boolean} [capture]
	* @param {boolean} [passive]
	* @returns {void}
	*/
	function event(event_name, dom, handler, capture, passive) {
		var options = {
			capture,
			passive
		};
		var target_handler = create_event(event_name, dom, handler, options);
		if (dom === document.body || dom === window || dom === document || dom instanceof HTMLMediaElement) teardown(() => {
			dom.removeEventListener(event_name, target_handler, options);
		});
	}
	/**
	* @param {string} event_name
	* @param {Element} element
	* @param {EventListener} [handler]
	* @returns {void}
	*/
	function delegated(event_name, element, handler) {
		(element[event_symbol] ??= {})[event_name] = handler;
	}
	/**
	* @param {Array<string>} events
	* @returns {void}
	*/
	function delegate(events) {
		for (var i = 0; i < events.length; i++) all_registered_events.add(events[i]);
		for (var fn of root_event_handles) fn(events);
	}
	var last_propagated_event = null;
	/**
	* @this {EventTarget}
	* @param {Event} event
	* @returns {void}
	*/
	function handle_event_propagation(event) {
		var handler_element = this;
		var owner_document = handler_element.ownerDocument;
		var event_name = event.type;
		var path = event.composedPath?.() || [];
		var current_target = path[0] || event.target;
		last_propagated_event = event;
		var path_idx = 0;
		var handled_at = last_propagated_event === event && event[event_symbol];
		if (handled_at) {
			var at_idx = path.indexOf(handled_at);
			if (at_idx !== -1 && (handler_element === document || handler_element === window)) {
				event[event_symbol] = handler_element;
				return;
			}
			var handler_idx = path.indexOf(handler_element);
			if (handler_idx === -1) return;
			if (at_idx <= handler_idx) path_idx = at_idx;
		}
		current_target = path[path_idx] || event.target;
		if (current_target === handler_element) return;
		define_property(event, "currentTarget", {
			configurable: true,
			get() {
				return current_target || owner_document;
			}
		});
		var previous_reaction = active_reaction;
		var previous_effect = active_effect;
		set_active_reaction(null);
		set_active_effect(null);
		try {
			/**
			* @type {unknown}
			*/
			var throw_error;
			/**
			* @type {unknown[]}
			*/
			var other_errors = [];
			while (current_target !== null) {
				/** @type {null | Element} */
				var parent_element = current_target.assignedSlot || current_target.parentNode || current_target.host || null;
				try {
					var delegated = current_target[event_symbol]?.[event_name];
					if (delegated != null && (!current_target.disabled || event.target === current_target)) delegated.call(current_target, event);
				} catch (error) {
					if (throw_error) other_errors.push(error);
					else throw_error = error;
				}
				if (event.cancelBubble || parent_element === handler_element || parent_element === null) break;
				current_target = parent_element;
			}
			if (throw_error) {
				for (let error of other_errors) queueMicrotask(() => {
					throw error;
				});
				throw throw_error;
			}
		} finally {
			event[event_symbol] = handler_element;
			delete event.currentTarget;
			set_active_reaction(previous_reaction);
			set_active_effect(previous_effect);
		}
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/dom/reconciler.js
	var policy = globalThis?.window?.trustedTypes && /* @__PURE__ */ globalThis.window.trustedTypes.createPolicy("svelte-trusted-html", { createHTML: (html) => {
		return html;
	} });
	/** @param {string} html */
	function create_trusted_html(html) {
		return policy?.createHTML(html) ?? html;
	}
	/**
	* @param {string} html
	*/
	function create_fragment_from_html(html) {
		var elem = create_element("template");
		elem.innerHTML = create_trusted_html(html.replaceAll("<!>", "<!---->"));
		return elem.content;
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/dom/template.js
	/** @import { Effect, EffectNodes, TemplateNode } from '#client' */
	/** @import { TemplateStructure } from './types' */
	/**
	* @param {TemplateNode} start
	* @param {TemplateNode | null} end
	*/
	function assign_nodes(start, end) {
		var effect = active_effect;
		if (effect.nodes === null) effect.nodes = {
			start,
			end,
			a: null,
			t: null
		};
	}
	/**
	* @param {string} content
	* @param {number} flags
	* @returns {() => Node | Node[]}
	*/
	/* @__NO_SIDE_EFFECTS__ */
	function from_html(content, flags) {
		var is_fragment = (flags & 1) !== 0;
		var use_import_node = (flags & 2) !== 0;
		/** @type {Node} */
		var node;
		/**
		* Whether or not the first item is a text/element node. If not, we need to
		* create an additional comment node to act as `effect.nodes.start`
		*/
		var has_start = !content.startsWith("<!>");
		return () => {
			if (hydrating) {
				assign_nodes(hydrate_node, null);
				return hydrate_node;
			}
			if (node === void 0) {
				node = create_fragment_from_html(has_start ? content : "<!>" + content);
				if (!is_fragment) node = /* @__PURE__ */ get_first_child(node);
			}
			var clone = use_import_node || is_firefox ? document.importNode(node, true) : node.cloneNode(true);
			if (is_fragment) {
				var start = /* @__PURE__ */ get_first_child(clone);
				var end = clone.lastChild;
				assign_nodes(start, end);
			} else assign_nodes(clone, clone);
			return clone;
		};
	}
	/**
	* @returns {TemplateNode | DocumentFragment}
	*/
	function comment() {
		if (hydrating) {
			assign_nodes(hydrate_node, null);
			return hydrate_node;
		}
		var frag = document.createDocumentFragment();
		var start = document.createComment("");
		var anchor = create_text();
		frag.append(start, anchor);
		assign_nodes(start, anchor);
		return frag;
	}
	/**
	* Assign the created (or in hydration mode, traversed) dom elements to the current block
	* and insert the elements into the dom (in client mode).
	* @param {Text | Comment | Element} anchor
	* @param {DocumentFragment | Element} dom
	*/
	function append(anchor, dom) {
		if (hydrating) {
			var effect = active_effect;
			if ((effect.f & 32768) === 0 || effect.nodes.end === null) effect.nodes.end = hydrate_node;
			hydrate_next();
			return;
		}
		if (anchor === null) return;
		anchor.before(dom);
	}
	/**
	* Subset of delegated events which should be passive by default.
	* These two are already passive via browser defaults on window, document and body.
	* But since
	* - we're delegating them
	* - they happen often
	* - they apply to mobile which is generally less performant
	* we're marking them as passive by default for other elements, too.
	*/
	var PASSIVE_EVENTS = ["touchstart", "touchmove"];
	/**
	* Returns `true` if `name` is a passive event
	* @param {string} name
	*/
	function is_passive_event(name) {
		return PASSIVE_EVENTS.includes(name);
	}
	/**
	* @param {Element} text
	* @param {string} value
	* @returns {void}
	*/
	function set_text(text, value) {
		var str = value == null ? "" : typeof value === "object" ? `${value}` : value;
		if (str !== (text.__t ??= text.nodeValue)) {
			text.__t = str;
			text.nodeValue = `${str}`;
		}
	}
	/**
	* Mounts a component to the given target and returns the exports and potentially the props (if compiled with `accessors: true`) of the component.
	* Transitions will play during the initial render unless the `intro` option is set to `false`.
	*
	* @template {Record<string, any>} Props
	* @template {Record<string, any>} Exports
	* @param {ComponentType<SvelteComponent<Props>> | Component<Props, Exports, any>} component
	* @param {MountOptions<Props>} options
	* @returns {Exports}
	*/
	function mount(component, options) {
		return _mount(component, options);
	}
	/**
	* Hydrates a component on the given target and returns the exports and potentially the props (if compiled with `accessors: true`) of the component
	*
	* @template {Record<string, any>} Props
	* @template {Record<string, any>} Exports
	* @param {ComponentType<SvelteComponent<Props>> | Component<Props, Exports, any>} component
	* @param {{} extends Props ? {
	* 		target: Document | Element | ShadowRoot;
	* 		props?: Props;
	* 		events?: Record<string, (e: any) => any>;
	*  	context?: Map<any, any>;
	* 		intro?: boolean;
	* 		recover?: boolean;
	*		transformError?: (error: unknown) => unknown;
	* 	} : {
	* 		target: Document | Element | ShadowRoot;
	* 		props: Props;
	* 		events?: Record<string, (e: any) => any>;
	*  	context?: Map<any, any>;
	* 		intro?: boolean;
	* 		recover?: boolean;
	*		transformError?: (error: unknown) => unknown;
	* 	}} options
	* @returns {Exports}
	*/
	function hydrate(component, options) {
		init_operations();
		options.intro = options.intro ?? false;
		const target = options.target;
		const was_hydrating = hydrating;
		const previous_hydrate_node = hydrate_node;
		try {
			var anchor = /* @__PURE__ */ get_first_child(target);
			while (anchor && (anchor.nodeType !== 8 || anchor.data !== "[")) anchor = /* @__PURE__ */ get_next_sibling(anchor);
			if (!anchor) throw HYDRATION_ERROR;
			set_hydrating(true);
			set_hydrate_node(anchor);
			const instance = _mount(component, {
				...options,
				anchor
			});
			set_hydrating(false);
			return instance;
		} catch (error) {
			if (error instanceof Error && error.message.split("\n").some((line) => line.startsWith("https://svelte.dev/e/"))) throw error;
			if (error !== HYDRATION_ERROR) console.warn("Failed to hydrate: ", error);
			if (options.recover === false) hydration_failed();
			init_operations();
			clear_text_content(target);
			set_hydrating(false);
			return mount(component, options);
		} finally {
			set_hydrating(was_hydrating);
			set_hydrate_node(previous_hydrate_node);
		}
	}
	/** @type {Map<EventTarget, Map<string, number>>} */
	var listeners = /* @__PURE__ */ new Map();
	/**
	* @template {Record<string, any>} Exports
	* @param {ComponentType<SvelteComponent<any>> | Component<any>} Component
	* @param {MountOptions} options
	* @returns {Exports}
	*/
	function _mount(Component, { target, anchor, props = {}, events, context, intro = true, transformError }) {
		init_operations();
		/** @type {Exports} */
		var component = void 0;
		var unmount = component_root(() => {
			var anchor_node = anchor ?? target.appendChild(create_text());
			boundary(anchor_node, { pending: () => {} }, (anchor_node) => {
				push({});
				var ctx = component_context;
				if (context) ctx.c = context;
				if (events)
 /** @type {any} */ props.$$events = events;
				if (hydrating) assign_nodes(anchor_node, null);
				component = Component(anchor_node, props) || {};
				if (hydrating) {
					/** @type {Effect & { nodes: EffectNodes }} */ active_effect.nodes.end = hydrate_node;
					if (hydrate_node === null || hydrate_node.nodeType !== 8 || hydrate_node.data !== "]") {
						hydration_mismatch();
						throw HYDRATION_ERROR;
					}
				}
				pop();
			}, transformError);
			/** @type {Set<string>} */
			var registered_events = /* @__PURE__ */ new Set();
			/** @param {Array<string>} events */
			var event_handle = (events) => {
				for (var i = 0; i < events.length; i++) {
					var event_name = events[i];
					if (registered_events.has(event_name)) continue;
					registered_events.add(event_name);
					var passive = is_passive_event(event_name);
					for (const node of [target, document]) {
						var counts = listeners.get(node);
						if (counts === void 0) {
							counts = /* @__PURE__ */ new Map();
							listeners.set(node, counts);
						}
						var count = counts.get(event_name);
						if (count === void 0) {
							node.addEventListener(event_name, handle_event_propagation, { passive });
							counts.set(event_name, 1);
						} else counts.set(event_name, count + 1);
					}
				}
			};
			event_handle(array_from(all_registered_events));
			root_event_handles.add(event_handle);
			return () => {
				for (var event_name of registered_events) for (const node of [target, document]) {
					var counts = listeners.get(node);
					var count = counts.get(event_name);
					if (--count == 0) {
						node.removeEventListener(event_name, handle_event_propagation);
						counts.delete(event_name);
						if (counts.size === 0) listeners.delete(node);
					} else counts.set(event_name, count);
				}
				root_event_handles.delete(event_handle);
				if (anchor_node !== anchor) anchor_node.parentNode?.removeChild(anchor_node);
			};
		});
		mounted_components.set(component, unmount);
		return component;
	}
	/**
	* References of the components that were mounted or hydrated.
	* Uses a `WeakMap` to avoid memory leaks.
	*/
	var mounted_components = /* @__PURE__ */ new WeakMap();
	/**
	* Unmounts a component that was previously mounted using `mount` or `hydrate`.
	*
	* Since 5.13.0, if `options.outro` is `true`, [transitions](https://svelte.dev/docs/svelte/transition) will play before the component is removed from the DOM.
	*
	* Returns a `Promise` that resolves after transitions have completed if `options.outro` is true, or immediately otherwise (prior to 5.13.0, returns `void`).
	*
	* ```js
	* import { mount, unmount } from 'svelte';
	* import App from './App.svelte';
	*
	* const app = mount(App, { target: document.body });
	*
	* // later...
	* unmount(app, { outro: true });
	* ```
	* @param {Record<string, any>} component
	* @param {{ outro?: boolean }} [options]
	* @returns {Promise<void>}
	*/
	function unmount(component, options) {
		const fn = mounted_components.get(component);
		if (fn) {
			mounted_components.delete(component);
			return fn(options);
		}
		return Promise.resolve();
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/dom/blocks/branches.js
	/** @import { Effect, TemplateNode } from '#client' */
	/**
	* @typedef {{ effect: Effect, fragment: DocumentFragment }} Branch
	*/
	/**
	* @template Key
	*/
	var BranchManager = class {
		/** @type {TemplateNode} */
		anchor;
		/** @type {Map<Batch, Key>} */
		#batches = /* @__PURE__ */ new Map();
		/**
		* Map of keys to effects that are currently rendered in the DOM.
		* These effects are visible and actively part of the document tree.
		* Example:
		* ```
		* {#if condition}
		* 	foo
		* {:else}
		* 	bar
		* {/if}
		* ```
		* Can result in the entries `true->Effect` and `false->Effect`
		* @type {Map<Key, Effect>}
		*/
		#onscreen = /* @__PURE__ */ new Map();
		/**
		* Similar to #onscreen with respect to the keys, but contains branches that are not yet
		* in the DOM, because their insertion is deferred.
		* @type {Map<Key, Branch>}
		*/
		#offscreen = /* @__PURE__ */ new Map();
		/**
		* Keys of effects that are currently outroing
		* @type {Set<Key>}
		*/
		#outroing = /* @__PURE__ */ new Set();
		/**
		* Whether to pause (i.e. outro) on change, or destroy immediately.
		* This is necessary for `<svelte:element>`
		*/
		#transition = true;
		/**
		* @param {TemplateNode} anchor
		* @param {boolean} transition
		*/
		constructor(anchor, transition = true) {
			this.anchor = anchor;
			this.#transition = transition;
		}
		/**
		* @param {Batch} batch
		*/
		#commit = (batch) => {
			if (!this.#batches.has(batch)) return;
			var key = this.#batches.get(batch);
			var onscreen = this.#onscreen.get(key);
			if (onscreen) {
				resume_effect(onscreen);
				this.#outroing.delete(key);
			} else {
				var offscreen = this.#offscreen.get(key);
				if (offscreen) {
					this.#onscreen.set(key, offscreen.effect);
					this.#offscreen.delete(key);
					/** @type {TemplateNode} */ offscreen.fragment.lastChild.remove();
					this.anchor.before(offscreen.fragment);
					onscreen = offscreen.effect;
				}
			}
			for (const [b, k] of this.#batches) {
				this.#batches.delete(b);
				if (b === batch) break;
				const offscreen = this.#offscreen.get(k);
				if (offscreen) {
					destroy_effect(offscreen.effect);
					this.#offscreen.delete(k);
				}
			}
			for (const [k, effect] of this.#onscreen) {
				if (k === key || this.#outroing.has(k)) continue;
				const on_destroy = () => {
					if (Array.from(this.#batches.values()).includes(k)) {
						var fragment = document.createDocumentFragment();
						move_effect(effect, fragment);
						fragment.append(create_text());
						this.#offscreen.set(k, {
							effect,
							fragment
						});
					} else destroy_effect(effect);
					this.#outroing.delete(k);
					this.#onscreen.delete(k);
				};
				if (this.#transition || !onscreen) {
					this.#outroing.add(k);
					pause_effect(effect, on_destroy, false);
				} else on_destroy();
			}
		};
		/**
		* @param {Batch} batch
		*/
		#discard = (batch) => {
			this.#batches.delete(batch);
			const keys = Array.from(this.#batches.values());
			for (const [k, branch] of this.#offscreen) if (!keys.includes(k)) {
				destroy_effect(branch.effect);
				this.#offscreen.delete(k);
			}
		};
		/**
		*
		* @param {any} key
		* @param {null | ((target: TemplateNode) => void)} fn
		*/
		ensure(key, fn) {
			var batch = current_batch;
			var defer = should_defer_append();
			if (fn && !this.#onscreen.has(key) && !this.#offscreen.has(key)) if (defer) {
				var fragment = document.createDocumentFragment();
				var target = create_text();
				fragment.append(target);
				this.#offscreen.set(key, {
					effect: branch(() => fn(target)),
					fragment
				});
			} else this.#onscreen.set(key, branch(() => fn(this.anchor)));
			this.#batches.set(batch, key);
			if (defer) {
				for (const [k, effect] of this.#onscreen) if (k === key) batch.unskip_effect(effect);
				else batch.skip_effect(effect);
				for (const [k, branch] of this.#offscreen) if (k === key) batch.unskip_effect(branch.effect);
				else batch.skip_effect(branch.effect);
				batch.oncommit(this.#commit);
				batch.ondiscard(this.#discard);
			} else {
				if (hydrating) this.anchor = hydrate_node;
				this.#commit(batch);
			}
		}
	};
	//#endregion
	//#region node_modules/svelte/src/internal/client/dom/blocks/snippet.js
	/** @import { Snippet } from 'svelte' */
	/** @import { TemplateNode } from '#client' */
	/** @import { Getters } from '#shared' */
	/**
	* @template {(node: TemplateNode, ...args: any[]) => void} SnippetFn
	* @param {TemplateNode} node
	* @param {() => SnippetFn | null | undefined} get_snippet
	* @param {(() => any)[]} args
	* @returns {void}
	*/
	function snippet(node, get_snippet, ...args) {
		var branches = new BranchManager(node);
		block(() => {
			const snippet = get_snippet() ?? null;
			branches.ensure(snippet, snippet && ((anchor) => snippet(anchor, ...args)));
		}, EFFECT_TRANSPARENT);
	}
	/**
	* `onMount`, like [`$effect`](https://svelte.dev/docs/svelte/$effect), schedules a function to run as soon as the component has been mounted to the DOM.
	* Unlike `$effect`, the provided function only runs once.
	*
	* It must be called during the component's initialisation (but doesn't need to live _inside_ the component;
	* it can be called from an external module). If a function is returned _synchronously_ from `onMount`,
	* it will be called when the component is unmounted.
	*
	* `onMount` functions do not run during [server-side rendering](https://svelte.dev/docs/svelte/svelte-server#render).
	*
	* @template T
	* @param {() => NotFunction<T> | Promise<NotFunction<T>> | (() => any)} fn
	* @returns {void}
	*/
	function onMount(fn) {
		if (component_context === null) lifecycle_outside_component("onMount");
		if (legacy_mode_flag && component_context.l !== null) init_update_callbacks(component_context).m.push(fn);
		else user_effect(() => {
			const cleanup = untrack(fn);
			if (typeof cleanup === "function") return cleanup;
		});
	}
	/**
	* Schedules a callback to run immediately before the component is unmounted.
	*
	* Out of `onMount`, `beforeUpdate`, `afterUpdate` and `onDestroy`, this is the
	* only one that runs inside a server-side component.
	*
	* @param {() => any} fn
	* @returns {void}
	*/
	function onDestroy(fn) {
		if (component_context === null) lifecycle_outside_component("onDestroy");
		onMount(() => () => untrack(fn));
	}
	/**
	* Legacy-mode: Init callbacks object for onMount/beforeUpdate/afterUpdate
	* @param {ComponentContext} context
	*/
	function init_update_callbacks(context) {
		var l = context.l;
		return l.u ??= {
			a: [],
			b: [],
			m: []
		};
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/dom/blocks/if.js
	/** @import { TemplateNode } from '#client' */
	/**
	* @param {TemplateNode} node
	* @param {(branch: (fn: (anchor: Node) => void, key?: number | false) => void) => void} fn
	* @param {boolean} [elseif] True if this is an `{:else if ...}` block rather than an `{#if ...}`, as that affects which transitions are considered 'local'
	* @returns {void}
	*/
	function if_block(node, fn, elseif = false) {
		/** @type {TemplateNode | undefined} */
		var marker;
		if (hydrating) {
			marker = hydrate_node;
			hydrate_next();
		}
		var branches = new BranchManager(node);
		var flags = elseif ? EFFECT_TRANSPARENT : 0;
		/**
		* @param {number | false} key
		* @param {null | ((anchor: Node) => void)} fn
		*/
		function update_branch(key, fn) {
			if (hydrating) {
				var data = read_hydration_instruction(marker);
				if (key !== parseInt(data.substring(1))) {
					var anchor = skip_nodes();
					set_hydrate_node(anchor);
					branches.anchor = anchor;
					set_hydrating(false);
					branches.ensure(key, fn);
					set_hydrating(true);
					return;
				}
			}
			branches.ensure(key, fn);
		}
		block(() => {
			var has_branch = false;
			fn((fn, key = 0) => {
				has_branch = true;
				update_branch(key, fn);
			});
			if (!has_branch) update_branch(-1, null);
		}, flags);
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/dom/blocks/each.js
	/** @import { EachItem, EachOutroGroup, EachState, Effect, EffectNodes, MaybeSource, Source, TemplateNode, TransitionManager, Value } from '#client' */
	/** @import { Batch } from '../../reactivity/batch.js'; */
	/**
	* @param {any} _
	* @param {number} i
	*/
	function index(_, i) {
		return i;
	}
	/**
	* Pause multiple effects simultaneously, and coordinate their
	* subsequent destruction. Used in each blocks
	* @param {EachState} state
	* @param {Effect[]} to_destroy
	* @param {null | Node} controlled_anchor
	*/
	function pause_effects(state, to_destroy, controlled_anchor) {
		/** @type {TransitionManager[]} */
		var transitions = [];
		var length = to_destroy.length;
		/** @type {EachOutroGroup} */
		var group;
		var remaining = to_destroy.length;
		for (var i = 0; i < length; i++) {
			let effect = to_destroy[i];
			pause_effect(effect, () => {
				if (group) {
					group.pending.delete(effect);
					group.done.add(effect);
					if (group.pending.size === 0) {
						var groups = state.outrogroups;
						destroy_effects(state, array_from(group.done));
						groups.delete(group);
						if (groups.size === 0) state.outrogroups = null;
					}
				} else remaining -= 1;
			}, false);
		}
		if (remaining === 0) {
			var fast_path = transitions.length === 0 && controlled_anchor !== null;
			if (fast_path) {
				var anchor = controlled_anchor;
				var parent_node = anchor.parentNode;
				clear_text_content(parent_node);
				parent_node.append(anchor);
				state.items.clear();
			}
			destroy_effects(state, to_destroy, !fast_path);
		} else {
			group = {
				pending: new Set(to_destroy),
				done: /* @__PURE__ */ new Set()
			};
			(state.outrogroups ??= /* @__PURE__ */ new Set()).add(group);
		}
	}
	/**
	* @param {EachState} state
	* @param {Effect[]} to_destroy
	* @param {boolean} remove_dom
	*/
	function destroy_effects(state, to_destroy, remove_dom = true) {
		/** @type {Set<Effect> | undefined} */
		var preserved_effects;
		if (state.pending.size > 0) {
			preserved_effects = /* @__PURE__ */ new Set();
			for (const keys of state.pending.values()) for (const key of keys) preserved_effects.add(
				/** @type {EachItem} */
				state.items.get(key).e
			);
		}
		for (var i = 0; i < to_destroy.length; i++) {
			var e = to_destroy[i];
			if (preserved_effects?.has(e)) {
				e.f |= EFFECT_OFFSCREEN;
				move_effect(e, document.createDocumentFragment());
			} else destroy_effect(to_destroy[i], remove_dom);
		}
	}
	/** @type {TemplateNode} */
	var offscreen_anchor;
	/**
	* @template V
	* @param {Element | Comment} node The next sibling node, or the parent node if this is a 'controlled' block
	* @param {number} flags
	* @param {() => V[]} get_collection
	* @param {(value: V, index: number) => any} get_key
	* @param {(anchor: Node, item: MaybeSource<V>, index: MaybeSource<number>) => void} render_fn
	* @param {null | ((anchor: Node) => void)} fallback_fn
	* @returns {void}
	*/
	function each(node, flags, get_collection, get_key, render_fn, fallback_fn = null) {
		var anchor = node;
		/** @type {Map<any, EachItem>} */
		var items = /* @__PURE__ */ new Map();
		if ((flags & 4) !== 0) {
			var parent_node = node;
			anchor = hydrating ? set_hydrate_node(/* @__PURE__ */ get_first_child(parent_node)) : parent_node.appendChild(create_text());
		}
		if (hydrating) hydrate_next();
		/** @type {Effect | null} */
		var fallback = null;
		var each_array = /* @__PURE__ */ derived_safe_equal(() => {
			var collection = get_collection();
			return is_array(collection) ? collection : collection == null ? [] : array_from(collection);
		});
		/** @type {V[]} */
		var array;
		/** @type {Map<Batch, Set<any>>} */
		var pending = /* @__PURE__ */ new Map();
		var first_run = true;
		/**
		* @param {Batch} batch
		*/
		function commit(batch) {
			if ((state.effect.f & 16384) !== 0) return;
			state.pending.delete(batch);
			state.fallback = fallback;
			reconcile(state, array, anchor, flags, get_key);
			if (fallback !== null) if (array.length === 0) if ((fallback.f & 33554432) === 0) resume_effect(fallback);
			else {
				fallback.f ^= EFFECT_OFFSCREEN;
				move(fallback, null, anchor);
			}
			else pause_effect(fallback, () => {
				fallback = null;
			});
		}
		/**
		* @param {Batch} batch
		*/
		function discard(batch) {
			state.pending.delete(batch);
		}
		/** @type {EachState} */
		var state = {
			effect: block(() => {
				array = get(each_array);
				var length = array.length;
				/** `true` if there was a hydration mismatch. Needs to be a `let` or else it isn't treeshaken out */
				let mismatch = false;
				if (hydrating) {
					if (read_hydration_instruction(anchor) === "[!" !== (length === 0)) {
						anchor = skip_nodes();
						set_hydrate_node(anchor);
						set_hydrating(false);
						mismatch = true;
					}
				}
				var keys = /* @__PURE__ */ new Set();
				var batch = current_batch;
				var defer = should_defer_append();
				for (var index = 0; index < length; index += 1) {
					if (hydrating && hydrate_node.nodeType === 8 && hydrate_node.data === "]") {
						anchor = hydrate_node;
						mismatch = true;
						set_hydrating(false);
					}
					var value = array[index];
					var key = get_key(value, index);
					var item = first_run ? null : items.get(key);
					if (item) {
						if (item.v) internal_set(item.v, value);
						if (item.i) internal_set(item.i, index);
						if (defer) batch.unskip_effect(item.e);
					} else {
						item = create_item(items, first_run ? anchor : offscreen_anchor ??= create_text(), value, key, index, render_fn, flags, get_collection);
						if (!first_run) item.e.f |= EFFECT_OFFSCREEN;
						items.set(key, item);
					}
					keys.add(key);
				}
				if (length === 0 && fallback_fn && !fallback) if (first_run) fallback = branch(() => fallback_fn(anchor));
				else {
					fallback = branch(() => fallback_fn(offscreen_anchor ??= create_text()));
					fallback.f |= EFFECT_OFFSCREEN;
				}
				if (length > keys.size) each_key_duplicate("", "", "");
				if (hydrating && length > 0) set_hydrate_node(skip_nodes());
				if (!first_run) {
					pending.set(batch, keys);
					if (defer) {
						for (const [key, item] of items) if (!keys.has(key)) batch.skip_effect(item.e);
						batch.oncommit(commit);
						batch.ondiscard(discard);
					} else commit(batch);
				}
				if (mismatch) set_hydrating(true);
				get(each_array);
			}),
			flags,
			items,
			pending,
			outrogroups: null,
			fallback
		};
		first_run = false;
		if (hydrating) anchor = hydrate_node;
	}
	/**
	* Skip past any non-branch effects (which could be created with `createSubscriber`, for example) to find the next branch effect
	* @param {Effect | null} effect
	* @returns {Effect | null}
	*/
	function skip_to_branch(effect) {
		while (effect !== null && (effect.f & 32) === 0) effect = effect.next;
		return effect;
	}
	/**
	* Add, remove, or reorder items output by an each block as its input changes
	* @template V
	* @param {EachState} state
	* @param {Array<V>} array
	* @param {Element | Comment | Text} anchor
	* @param {number} flags
	* @param {(value: V, index: number) => any} get_key
	* @returns {void}
	*/
	function reconcile(state, array, anchor, flags, get_key) {
		var is_animated = (flags & 8) !== 0;
		var length = array.length;
		var items = state.items;
		var current = skip_to_branch(state.effect.first);
		/** @type {undefined | Set<Effect>} */
		var seen;
		/** @type {Effect | null} */
		var prev = null;
		/** @type {undefined | Set<Effect>} */
		var to_animate;
		/** @type {Effect[]} */
		var matched = [];
		/** @type {Effect[]} */
		var stashed = [];
		/** @type {V} */
		var value;
		/** @type {any} */
		var key;
		/** @type {Effect | undefined} */
		var effect;
		/** @type {number} */
		var i;
		if (is_animated) for (i = 0; i < length; i += 1) {
			value = array[i];
			key = get_key(value, i);
			effect = items.get(key).e;
			if ((effect.f & 33554432) === 0) {
				effect.nodes?.a?.measure();
				(to_animate ??= /* @__PURE__ */ new Set()).add(effect);
			}
		}
		for (i = 0; i < length; i += 1) {
			value = array[i];
			key = get_key(value, i);
			effect = items.get(key).e;
			if (state.outrogroups !== null) for (const group of state.outrogroups) {
				group.pending.delete(effect);
				group.done.delete(effect);
			}
			if ((effect.f & 8192) !== 0) {
				resume_effect(effect);
				if (is_animated) {
					effect.nodes?.a?.unfix();
					(to_animate ??= /* @__PURE__ */ new Set()).delete(effect);
				}
			}
			if ((effect.f & 33554432) !== 0) {
				effect.f ^= EFFECT_OFFSCREEN;
				if (effect === current) move(effect, null, anchor);
				else {
					var next = prev ? prev.next : current;
					if (effect === state.effect.last) state.effect.last = effect.prev;
					if (effect.prev) effect.prev.next = effect.next;
					if (effect.next) effect.next.prev = effect.prev;
					link(state, prev, effect);
					link(state, effect, next);
					move(effect, next, anchor);
					prev = effect;
					matched = [];
					stashed = [];
					current = skip_to_branch(prev.next);
					continue;
				}
			}
			if (effect !== current) {
				if (seen !== void 0 && seen.has(effect)) {
					if (matched.length < stashed.length) {
						var start = stashed[0];
						var j;
						prev = start.prev;
						var a = matched[0];
						var b = matched[matched.length - 1];
						for (j = 0; j < matched.length; j += 1) move(matched[j], start, anchor);
						for (j = 0; j < stashed.length; j += 1) seen.delete(stashed[j]);
						link(state, a.prev, b.next);
						link(state, prev, a);
						link(state, b, start);
						current = start;
						prev = b;
						i -= 1;
						matched = [];
						stashed = [];
					} else {
						seen.delete(effect);
						move(effect, current, anchor);
						link(state, effect.prev, effect.next);
						link(state, effect, prev === null ? state.effect.first : prev.next);
						link(state, prev, effect);
						prev = effect;
					}
					continue;
				}
				matched = [];
				stashed = [];
				while (current !== null && current !== effect) {
					(seen ??= /* @__PURE__ */ new Set()).add(current);
					stashed.push(current);
					current = skip_to_branch(current.next);
				}
				if (current === null) continue;
			}
			if ((effect.f & 33554432) === 0) matched.push(effect);
			prev = effect;
			current = skip_to_branch(effect.next);
		}
		if (state.outrogroups !== null) {
			for (const group of state.outrogroups) if (group.pending.size === 0) {
				destroy_effects(state, array_from(group.done));
				state.outrogroups?.delete(group);
			}
			if (state.outrogroups.size === 0) state.outrogroups = null;
		}
		if (current !== null || seen !== void 0) {
			/** @type {Effect[]} */
			var to_destroy = [];
			if (seen !== void 0) {
				for (effect of seen) if ((effect.f & 8192) === 0) to_destroy.push(effect);
			}
			while (current !== null) {
				if ((current.f & 8192) === 0 && current !== state.fallback) to_destroy.push(current);
				current = skip_to_branch(current.next);
			}
			var destroy_length = to_destroy.length;
			if (destroy_length > 0) {
				var controlled_anchor = (flags & 4) !== 0 && length === 0 ? anchor : null;
				if (is_animated) {
					for (i = 0; i < destroy_length; i += 1) to_destroy[i].nodes?.a?.measure();
					for (i = 0; i < destroy_length; i += 1) to_destroy[i].nodes?.a?.fix();
				}
				pause_effects(state, to_destroy, controlled_anchor);
			}
		}
		if (is_animated) queue_micro_task(() => {
			if (to_animate === void 0) return;
			for (effect of to_animate) effect.nodes?.a?.apply();
		});
	}
	/**
	* @template V
	* @param {Map<any, EachItem>} items
	* @param {Node} anchor
	* @param {V} value
	* @param {unknown} key
	* @param {number} index
	* @param {(anchor: Node, item: V | Source<V>, index: number | Value<number>, collection: () => V[]) => void} render_fn
	* @param {number} flags
	* @param {() => V[]} get_collection
	* @returns {EachItem}
	*/
	function create_item(items, anchor, value, key, index, render_fn, flags, get_collection) {
		var v = (flags & 1) !== 0 ? (flags & 16) === 0 ? /* @__PURE__ */ mutable_source(value, false, false) : source(value) : null;
		var i = (flags & 2) !== 0 ? source(index) : null;
		return {
			v,
			i,
			e: branch(() => {
				render_fn(anchor, v ?? value, i ?? index, get_collection);
				return () => {
					items.delete(key);
				};
			})
		};
	}
	/**
	* @param {Effect} effect
	* @param {Effect | null} next
	* @param {Text | Element | Comment} anchor
	*/
	function move(effect, next, anchor) {
		if (!effect.nodes) return;
		var node = effect.nodes.start;
		var end = effect.nodes.end;
		var dest = next && (next.f & 33554432) === 0 ? next.nodes.start : anchor;
		while (node !== null) {
			var next_node = /* @__PURE__ */ get_next_sibling(node);
			dest.before(node);
			if (node === end) return;
			node = next_node;
		}
	}
	/**
	* @param {EachState} state
	* @param {Effect | null} prev
	* @param {Effect | null} next
	*/
	function link(state, prev, next) {
		if (prev === null) state.effect.first = next;
		else prev.next = next;
		if (next === null) state.effect.last = prev;
		else next.prev = prev;
	}
	/**
	* @param {Element | Text | Comment} node
	* @param {() => string | TrustedHTML} get_value
	* @param {boolean} [is_controlled]
	* @param {boolean} [svg]
	* @param {boolean} [mathml]
	* @param {boolean} [skip_warning]
	* @returns {void}
	*/
	function html$2(node, get_value, is_controlled = false, svg = false, mathml = false, skip_warning = false) {
		var anchor = node;
		/** @type {string | TrustedHTML} */
		var value = "";
		if (is_controlled) {
			var parent_node = node;
			if (hydrating) anchor = set_hydrate_node(/* @__PURE__ */ get_first_child(parent_node));
		}
		template_effect(() => {
			var effect = active_effect;
			if (value === (value = get_value() ?? "")) {
				if (hydrating) hydrate_next();
				return;
			}
			if (is_controlled && !hydrating) {
				effect.nodes = null;
				parent_node.innerHTML = value;
				if (value !== "") assign_nodes(/* @__PURE__ */ get_first_child(parent_node), parent_node.lastChild);
				return;
			}
			if (effect.nodes !== null) {
				remove_effect_dom(effect.nodes.start, effect.nodes.end);
				effect.nodes = null;
			}
			if (value === "") return;
			if (hydrating) {
				hydrate_node.data;
				/** @type {TemplateNode | null} */
				var next = hydrate_next();
				var last = next;
				while (next !== null && (next.nodeType !== 8 || next.data !== "")) {
					last = next;
					next = /* @__PURE__ */ get_next_sibling(next);
				}
				if (next === null) {
					hydration_mismatch();
					throw HYDRATION_ERROR;
				}
				assign_nodes(hydrate_node, last);
				anchor = set_hydrate_node(next);
				return;
			}
			var wrapper = create_element(svg ? "svg" : mathml ? "math" : "template", svg ? NAMESPACE_SVG : mathml ? NAMESPACE_MATHML : void 0);
			wrapper.innerHTML = value;
			/** @type {DocumentFragment | Element} */
			var node = svg || mathml ? wrapper : wrapper.content;
			assign_nodes(/* @__PURE__ */ get_first_child(node), node.lastChild);
			if (svg || mathml) while (/* @__PURE__ */ get_first_child(node)) anchor.before(/* @__PURE__ */ get_first_child(node));
			else anchor.before(node);
		});
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/dom/css.js
	/**
	* @param {Node} anchor
	* @param {{ hash: string, code: string }} css
	*/
	function append_styles$1(anchor, css) {
		effect(() => {
			var root = anchor.getRootNode();
			var target = root.host ? root : root.head ?? root.ownerDocument.head;
			if (!target.querySelector("#" + css.hash)) {
				const style = create_element("style");
				style.id = css.hash;
				style.textContent = css.code;
				target.appendChild(style);
			}
		});
	}
	//#endregion
	//#region node_modules/clsx/dist/clsx.mjs
	function r(e) {
		var t, f, n = "";
		if ("string" == typeof e || "number" == typeof e) n += e;
		else if ("object" == typeof e) if (Array.isArray(e)) {
			var o = e.length;
			for (t = 0; t < o; t++) e[t] && (f = r(e[t])) && (n && (n += " "), n += f);
		} else for (f in e) e[f] && (n && (n += " "), n += f);
		return n;
	}
	function clsx$1() {
		for (var e, t, f = 0, n = "", o = arguments.length; f < o; f++) (e = arguments[f]) && (t = r(e)) && (n && (n += " "), n += t);
		return n;
	}
	//#endregion
	//#region node_modules/svelte/src/internal/shared/attributes.js
	/**
	* Small wrapper around clsx to preserve Svelte's (weird) handling of falsy values.
	* TODO Svelte 6 revisit this, and likely turn all falsy values into the empty string (what clsx also does)
	* @param  {any} value
	*/
	function clsx(value) {
		if (typeof value === "object") return clsx$1(value);
		else return value ?? "";
	}
	var whitespace = [..." 	\n\r\f\xA0\v﻿"];
	/**
	* @param {any} value
	* @param {string | null} [hash]
	* @param {Record<string, boolean>} [directives]
	* @returns {string | null}
	*/
	function to_class(value, hash, directives) {
		var classname = value == null ? "" : "" + value;
		if (hash) classname = classname ? classname + " " + hash : hash;
		if (directives) {
			for (var key of Object.keys(directives)) if (directives[key]) classname = classname ? classname + " " + key : key;
			else if (classname.length) {
				var len = key.length;
				var a = 0;
				while ((a = classname.indexOf(key, a)) >= 0) {
					var b = a + len;
					if ((a === 0 || whitespace.includes(classname[a - 1])) && (b === classname.length || whitespace.includes(classname[b]))) classname = (a === 0 ? "" : classname.substring(0, a)) + classname.substring(b + 1);
					else a = b;
				}
			}
		}
		return classname === "" ? null : classname;
	}
	/**
	*
	* @param {Record<string,any>} styles
	* @param {boolean} important
	*/
	function append_styles(styles, important = false) {
		var separator = important ? " !important;" : ";";
		var css = "";
		for (var key of Object.keys(styles)) {
			var value = styles[key];
			if (value != null && value !== "") css += " " + key + ": " + value + separator;
		}
		return css;
	}
	/**
	* @param {string} name
	* @returns {string}
	*/
	function to_css_name(name) {
		if (name[0] !== "-" || name[1] !== "-") return name.toLowerCase();
		return name;
	}
	/**
	* @param {any} value
	* @param {Record<string, any> | [Record<string, any>, Record<string, any>]} [styles]
	* @returns {string | null}
	*/
	function to_style(value, styles) {
		if (styles) {
			var new_style = "";
			/** @type {Record<string,any> | undefined} */
			var normal_styles;
			/** @type {Record<string,any> | undefined} */
			var important_styles;
			if (Array.isArray(styles)) {
				normal_styles = styles[0];
				important_styles = styles[1];
			} else normal_styles = styles;
			if (value) {
				value = String(value).replaceAll(/\s*\/\*.*?\*\/\s*/g, "").trim();
				/** @type {boolean | '"' | "'"} */
				var in_str = false;
				var in_apo = 0;
				var in_comment = false;
				var reserved_names = [];
				if (normal_styles) reserved_names.push(...Object.keys(normal_styles).map(to_css_name));
				if (important_styles) reserved_names.push(...Object.keys(important_styles).map(to_css_name));
				var start_index = 0;
				var name_index = -1;
				const len = value.length;
				for (var i = 0; i < len; i++) {
					var c = value[i];
					if (in_comment) {
						if (c === "/" && value[i - 1] === "*") in_comment = false;
					} else if (in_str) {
						if (in_str === c) in_str = false;
					} else if (c === "/" && value[i + 1] === "*") in_comment = true;
					else if (c === "\"" || c === "'") in_str = c;
					else if (c === "(") in_apo++;
					else if (c === ")") in_apo--;
					if (!in_comment && in_str === false && in_apo === 0) {
						if (c === ":" && name_index === -1) name_index = i;
						else if (c === ";" || i === len - 1) {
							if (name_index !== -1) {
								var name = to_css_name(value.substring(start_index, name_index).trim());
								if (!reserved_names.includes(name)) {
									if (c !== ";") i++;
									var property = value.substring(start_index, i).trim();
									new_style += " " + property + ";";
								}
							}
							start_index = i + 1;
							name_index = -1;
						}
					}
				}
			}
			if (normal_styles) new_style += append_styles(normal_styles);
			if (important_styles) new_style += append_styles(important_styles, true);
			new_style = new_style.trim();
			return new_style === "" ? null : new_style;
		}
		return value == null ? null : String(value);
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/dom/elements/class.js
	/**
	* @param {Element} dom
	* @param {boolean | number} is_html
	* @param {string | null} value
	* @param {string} [hash]
	* @param {Record<string, any>} [prev_classes]
	* @param {Record<string, any>} [next_classes]
	* @returns {Record<string, boolean> | undefined}
	*/
	function set_class(dom, is_html, value, hash, prev_classes, next_classes) {
		var prev = dom.__className;
		if (hydrating || prev !== value || prev === void 0) {
			var next_class_name = to_class(value, hash, next_classes);
			if (!hydrating || next_class_name !== dom.getAttribute("class")) if (next_class_name == null) dom.removeAttribute("class");
			else if (is_html) dom.className = next_class_name;
			else dom.setAttribute("class", next_class_name);
			dom.__className = value;
		} else if (next_classes && prev_classes !== next_classes) for (var key in next_classes) {
			var is_present = !!next_classes[key];
			if (prev_classes == null || is_present !== !!prev_classes[key]) dom.classList.toggle(key, is_present);
		}
		return next_classes;
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/dom/elements/style.js
	/**
	* @param {Element & ElementCSSInlineStyle} dom
	* @param {Record<string, any>} prev
	* @param {Record<string, any>} next
	* @param {string} [priority]
	*/
	function update_styles(dom, prev = {}, next, priority) {
		for (var key in next) {
			var value = next[key];
			if (prev[key] !== value) if (next[key] == null) dom.style.removeProperty(key);
			else dom.style.setProperty(key, value, priority);
		}
	}
	/**
	* @param {Element & ElementCSSInlineStyle} dom
	* @param {string | null} value
	* @param {Record<string, any> | [Record<string, any>, Record<string, any>]} [prev_styles]
	* @param {Record<string, any> | [Record<string, any>, Record<string, any>]} [next_styles]
	*/
	function set_style(dom, value, prev_styles, next_styles) {
		var prev = dom.__style;
		if (hydrating || prev !== value) {
			var next_style_attr = to_style(value, next_styles);
			if (!hydrating || next_style_attr !== dom.getAttribute("style")) if (next_style_attr == null) dom.removeAttribute("style");
			else dom.style.cssText = next_style_attr;
			dom.__style = value;
		} else if (next_styles) if (Array.isArray(next_styles)) {
			update_styles(dom, prev_styles?.[0], next_styles[0]);
			update_styles(dom, prev_styles?.[1], next_styles[1], "important");
		} else update_styles(dom, prev_styles, next_styles);
		return next_styles;
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/dom/elements/attributes.js
	/** @import { Blocker, Effect } from '#client' */
	var IS_CUSTOM_ELEMENT = Symbol("is custom element");
	var IS_HTML = Symbol("is html");
	var LINK_TAG = IS_XHTML ? "link" : "LINK";
	/**
	* The value/checked attribute in the template actually corresponds to the defaultValue property, so we need
	* to remove it upon hydration to avoid a bug when someone resets the form value.
	* @param {HTMLInputElement} input
	* @returns {void}
	*/
	function remove_input_defaults(input) {
		if (!hydrating) return;
		var already_removed = false;
		var remove_defaults = () => {
			if (already_removed) return;
			already_removed = true;
			if (input.hasAttribute("value")) {
				var value = input.value;
				set_attribute(input, "value", null);
				input.value = value;
			}
			if (input.hasAttribute("checked")) {
				var checked = input.checked;
				set_attribute(input, "checked", null);
				input.checked = checked;
			}
		};
		input.__on_r = remove_defaults;
		queue_micro_task(remove_defaults);
		add_form_reset_listener();
	}
	/**
	* @param {Element} element
	* @param {string} attribute
	* @param {string | null} value
	* @param {boolean} [skip_warning]
	*/
	function set_attribute(element, attribute, value, skip_warning) {
		var attributes = get_attributes(element);
		if (hydrating) {
			attributes[attribute] = element.getAttribute(attribute);
			if (attribute === "src" || attribute === "srcset" || attribute === "href" && element.nodeName === LINK_TAG) {
				if (!skip_warning) check_src_in_dev_hydration(element, attribute, value ?? "");
				return;
			}
		}
		if (attributes[attribute] === (attributes[attribute] = value)) return;
		if (attribute === "loading") element[LOADING_ATTR_SYMBOL] = value;
		if (value == null) element.removeAttribute(attribute);
		else if (typeof value !== "string" && get_setters(element).includes(attribute)) element[attribute] = value;
		else element.setAttribute(attribute, value);
	}
	/**
	*
	* @param {Element} element
	*/
	function get_attributes(element) {
		return element.__attributes ??= {
			[IS_CUSTOM_ELEMENT]: element.nodeName.includes("-"),
			[IS_HTML]: element.namespaceURI === NAMESPACE_HTML
		};
	}
	/** @type {Map<string, string[]>} */
	var setters_cache = /* @__PURE__ */ new Map();
	/** @param {Element} element */
	function get_setters(element) {
		var cache_key = element.getAttribute("is") || element.nodeName;
		var setters = setters_cache.get(cache_key);
		if (setters) return setters;
		setters_cache.set(cache_key, setters = []);
		var descriptors;
		var proto = element;
		var element_proto = Element.prototype;
		while (element_proto !== proto) {
			descriptors = get_descriptors(proto);
			for (var key in descriptors) if (descriptors[key].set) setters.push(key);
			proto = get_prototype_of(proto);
		}
		return setters;
	}
	/**
	* @param {any} element
	* @param {string} attribute
	* @param {string} value
	*/
	function check_src_in_dev_hydration(element, attribute, value) {}
	//#endregion
	//#region node_modules/svelte/src/internal/client/dom/elements/bindings/input.js
	/** @import { Batch } from '../../../reactivity/batch.js' */
	/**
	* @param {HTMLInputElement} input
	* @param {() => unknown} get
	* @param {(value: unknown) => void} set
	* @returns {void}
	*/
	function bind_value(input, get, set = get) {
		var batches = /* @__PURE__ */ new WeakSet();
		listen_to_event_and_reset_event(input, "input", async (is_reset) => {
			/** @type {any} */
			var value = is_reset ? input.defaultValue : input.value;
			value = is_numberlike_input(input) ? to_number(value) : value;
			set(value);
			if (current_batch !== null) batches.add(current_batch);
			await tick();
			if (value !== (value = get())) {
				var start = input.selectionStart;
				var end = input.selectionEnd;
				var length = input.value.length;
				input.value = value ?? "";
				if (end !== null) {
					var new_length = input.value.length;
					if (start === end && end === length && new_length > length) {
						input.selectionStart = new_length;
						input.selectionEnd = new_length;
					} else {
						input.selectionStart = start;
						input.selectionEnd = Math.min(end, new_length);
					}
				}
			}
		});
		if (hydrating && input.defaultValue !== input.value || untrack(get) == null && input.value) {
			set(is_numberlike_input(input) ? to_number(input.value) : input.value);
			if (current_batch !== null) batches.add(current_batch);
		}
		render_effect(() => {
			var value = get();
			if (input === document.activeElement) {
				var batch = async_mode_flag ? previous_batch : current_batch;
				if (batches.has(batch)) return;
			}
			if (is_numberlike_input(input) && value === to_number(input.value)) return;
			if (input.type === "date" && !value && !input.value) return;
			if (value !== input.value) input.value = value ?? "";
		});
	}
	/**
	* @param {HTMLInputElement} input
	*/
	function is_numberlike_input(input) {
		var type = input.type;
		return type === "number" || type === "range";
	}
	/**
	* @param {string} value
	*/
	function to_number(value) {
		return value === "" ? null : +value;
	}
	var resize_observer_border_box = /* @__PURE__ */ new class ResizeObserverSingleton {
		/** */
		#listeners = /* @__PURE__ */ new WeakMap();
		/** @type {ResizeObserver | undefined} */
		#observer;
		/** @type {ResizeObserverOptions} */
		#options;
		/** @static */
		static entries = /* @__PURE__ */ new WeakMap();
		/** @param {ResizeObserverOptions} options */
		constructor(options) {
			this.#options = options;
		}
		/**
		* @param {Element} element
		* @param {(entry: ResizeObserverEntry) => any} listener
		*/
		observe(element, listener) {
			var listeners = this.#listeners.get(element) || /* @__PURE__ */ new Set();
			listeners.add(listener);
			this.#listeners.set(element, listeners);
			this.#getObserver().observe(element, this.#options);
			return () => {
				var listeners = this.#listeners.get(element);
				listeners.delete(listener);
				if (listeners.size === 0) {
					this.#listeners.delete(element);
					/** @type {ResizeObserver} */ this.#observer.unobserve(element);
				}
			};
		}
		#getObserver() {
			return this.#observer ?? (this.#observer = new ResizeObserver(
				/** @param {any} entries */
				(entries) => {
					for (var entry of entries) {
						ResizeObserverSingleton.entries.set(entry.target, entry);
						for (var listener of this.#listeners.get(entry.target) || []) listener(entry);
					}
				}
			));
		}
	}({ box: "border-box" });
	/**
	* @param {HTMLElement} element
	* @param {'clientWidth' | 'clientHeight' | 'offsetWidth' | 'offsetHeight'} type
	* @param {(size: number) => void} set
	*/
	function bind_element_size(element, type, set) {
		var unsub = resize_observer_border_box.observe(element, () => set(element[type]));
		effect(() => {
			untrack(() => set(element[type]));
			return unsub;
		});
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/dom/elements/bindings/this.js
	/** @import { ComponentContext, Effect } from '#client' */
	/**
	* @param {any} bound_value
	* @param {Element} element_or_component
	* @returns {boolean}
	*/
	function is_bound_this(bound_value, element_or_component) {
		return bound_value === element_or_component || bound_value?.[STATE_SYMBOL] === element_or_component;
	}
	/**
	* @param {any} element_or_component
	* @param {(value: unknown, ...parts: unknown[]) => void} update
	* @param {(...parts: unknown[]) => unknown} get_value
	* @param {() => unknown[]} [get_parts] Set if the this binding is used inside an each block,
	* 										returns all the parts of the each block context that are used in the expression
	* @returns {void}
	*/
	function bind_this(element_or_component = {}, update, get_value, get_parts) {
		var component_effect = component_context.r;
		var parent = active_effect;
		effect(() => {
			/** @type {unknown[]} */
			var old_parts;
			/** @type {unknown[]} */
			var parts;
			render_effect(() => {
				old_parts = parts;
				parts = get_parts?.() || [];
				untrack(() => {
					if (element_or_component !== get_value(...parts)) {
						update(element_or_component, ...parts);
						if (old_parts && is_bound_this(get_value(...old_parts), element_or_component)) update(null, ...old_parts);
					}
				});
			});
			return () => {
				let p = parent;
				while (p !== component_effect && p.parent !== null && p.parent.f & 33554432) p = p.parent;
				const teardown = () => {
					if (parts && is_bound_this(get_value(...parts), element_or_component)) update(null, ...parts);
				};
				const original_teardown = p.teardown;
				p.teardown = () => {
					teardown();
					original_teardown?.();
				};
			};
		});
		return element_or_component;
	}
	//#endregion
	//#region node_modules/svelte/src/internal/client/reactivity/props.js
	/** @import { Effect, Source } from './types.js' */
	/**
	* This function is responsible for synchronizing a possibly bound prop with the inner component state.
	* It is used whenever the compiler sees that the component writes to the prop, or when it has a default prop_value.
	* @template V
	* @param {Record<string, unknown>} props
	* @param {string} key
	* @param {number} flags
	* @param {V | (() => V)} [fallback]
	* @returns {(() => V | ((arg: V) => V) | ((arg: V, mutation: boolean) => V))}
	*/
	function prop(props, key, flags, fallback) {
		var runes = !legacy_mode_flag || (flags & 2) !== 0;
		var bindable = (flags & 8) !== 0;
		var lazy = (flags & 16) !== 0;
		var fallback_value = fallback;
		var fallback_dirty = true;
		var get_fallback = () => {
			if (fallback_dirty) {
				fallback_dirty = false;
				fallback_value = lazy ? untrack(fallback) : fallback;
			}
			return fallback_value;
		};
		/** @type {((v: V) => void) | undefined} */
		let setter;
		if (bindable) {
			var is_entry_props = STATE_SYMBOL in props || LEGACY_PROPS in props;
			setter = get_descriptor(props, key)?.set ?? (is_entry_props && key in props ? (v) => props[key] = v : void 0);
		}
		/** @type {V} */
		var initial_value;
		var is_store_sub = false;
		if (bindable) [initial_value, is_store_sub] = capture_store_binding(() => props[key]);
		else initial_value = props[key];
		if (initial_value === void 0 && fallback !== void 0) {
			initial_value = get_fallback();
			if (setter) {
				if (runes) props_invalid_value(key);
				setter(initial_value);
			}
		}
		/** @type {() => V} */
		var getter;
		if (runes) getter = () => {
			var value = props[key];
			if (value === void 0) return get_fallback();
			fallback_dirty = true;
			return value;
		};
		else getter = () => {
			var value = props[key];
			if (value !== void 0) fallback_value = void 0;
			return value === void 0 ? fallback_value : value;
		};
		if (runes && (flags & 4) === 0) return getter;
		if (setter) {
			var legacy_parent = props.$$legacy;
			return (function(value, mutation) {
				if (arguments.length > 0) {
					if (!runes || !mutation || legacy_parent || is_store_sub)
 /** @type {Function} */ setter(mutation ? getter() : value);
					return value;
				}
				return getter();
			});
		}
		var overridden = false;
		var d = ((flags & 1) !== 0 ? derived : derived_safe_equal)(() => {
			overridden = false;
			return getter();
		});
		if (bindable) get(d);
		var parent_effect = active_effect;
		return (function(value, mutation) {
			if (arguments.length > 0) {
				const new_value = mutation ? get(d) : runes && bindable ? proxy(value) : value;
				set(d, new_value);
				overridden = true;
				if (fallback_value !== void 0) fallback_value = new_value;
				return value;
			}
			if (is_destroying_effect && overridden || (parent_effect.f & 16384) !== 0) return d.v;
			return get(d);
		});
	}
	//#endregion
	//#region node_modules/svelte/src/legacy/legacy-client.js
	/** @import { ComponentConstructorOptions, ComponentType, SvelteComponent, Component } from 'svelte' */
	/**
	* Takes the same options as a Svelte 4 component and the component function and returns a Svelte 4 compatible component.
	*
	* @deprecated Use this only as a temporary solution to migrate your imperative component code to Svelte 5.
	*
	* @template {Record<string, any>} Props
	* @template {Record<string, any>} Exports
	* @template {Record<string, any>} Events
	* @template {Record<string, any>} Slots
	*
	* @param {ComponentConstructorOptions<Props> & {
	* 	component: ComponentType<SvelteComponent<Props, Events, Slots>> | Component<Props>;
	* }} options
	* @returns {SvelteComponent<Props, Events, Slots> & Exports}
	*/
	function createClassComponent(options) {
		return new Svelte4Component(options);
	}
	/**
	* Support using the component as both a class and function during the transition period
	* @typedef  {{new (o: ComponentConstructorOptions): SvelteComponent;(...args: Parameters<Component<Record<string, any>>>): ReturnType<Component<Record<string, any>, Record<string, any>>>;}} LegacyComponentType
	*/
	var Svelte4Component = class {
		/** @type {any} */
		#events;
		/** @type {Record<string, any>} */
		#instance;
		/**
		* @param {ComponentConstructorOptions & {
		*  component: any;
		* }} options
		*/
		constructor(options) {
			var sources = /* @__PURE__ */ new Map();
			/**
			* @param {string | symbol} key
			* @param {unknown} value
			*/
			var add_source = (key, value) => {
				var s = /* @__PURE__ */ mutable_source(value, false, false);
				sources.set(key, s);
				return s;
			};
			const props = new Proxy({
				...options.props || {},
				$$events: {}
			}, {
				get(target, prop) {
					return get(sources.get(prop) ?? add_source(prop, Reflect.get(target, prop)));
				},
				has(target, prop) {
					if (prop === LEGACY_PROPS) return true;
					get(sources.get(prop) ?? add_source(prop, Reflect.get(target, prop)));
					return Reflect.has(target, prop);
				},
				set(target, prop, value) {
					set(sources.get(prop) ?? add_source(prop, value), value);
					return Reflect.set(target, prop, value);
				}
			});
			this.#instance = (options.hydrate ? hydrate : mount)(options.component, {
				target: options.target,
				anchor: options.anchor,
				props,
				context: options.context,
				intro: options.intro ?? false,
				recover: options.recover,
				transformError: options.transformError
			});
			if (!async_mode_flag && (!options?.props?.$$host || options.sync === false)) flushSync();
			this.#events = props.$$events;
			for (const key of Object.keys(this.#instance)) {
				if (key === "$set" || key === "$destroy" || key === "$on") continue;
				define_property(this, key, {
					get() {
						return this.#instance[key];
					},
					set(value) {
						this.#instance[key] = value;
					},
					enumerable: true
				});
			}
			this.#instance.$set = (next) => {
				Object.assign(props, next);
			};
			this.#instance.$destroy = () => {
				unmount(this.#instance);
			};
		}
		/** @param {Record<string, any>} props */
		$set(props) {
			this.#instance.$set(props);
		}
		/**
		* @param {string} event
		* @param {(...args: any[]) => any} callback
		* @returns {any}
		*/
		$on(event, callback) {
			this.#events[event] = this.#events[event] || [];
			/** @param {any[]} args */
			const cb = (...args) => callback.call(this, ...args);
			this.#events[event].push(cb);
			return () => {
				this.#events[event] = this.#events[event].filter(
					/** @param {any} fn */
					(fn) => fn !== cb
				);
			};
		}
		$destroy() {
			this.#instance.$destroy();
		}
	};
	//#endregion
	//#region node_modules/svelte/src/internal/client/dom/elements/custom-element.js
	/**
	* @typedef {Object} CustomElementPropDefinition
	* @property {string} [attribute]
	* @property {boolean} [reflect]
	* @property {'String'|'Boolean'|'Number'|'Array'|'Object'} [type]
	*/
	/** @type {any} */
	var SvelteElement;
	if (typeof HTMLElement === "function") SvelteElement = class extends HTMLElement {
		/** The Svelte component constructor */
		$$ctor;
		/** Slots */
		$$s;
		/** @type {any} The Svelte component instance */
		$$c;
		/** Whether or not the custom element is connected */
		$$cn = false;
		/** @type {Record<string, any>} Component props data */
		$$d = {};
		/** `true` if currently in the process of reflecting component props back to attributes */
		$$r = false;
		/** @type {Record<string, CustomElementPropDefinition>} Props definition (name, reflected, type etc) */
		$$p_d = {};
		/** @type {Record<string, EventListenerOrEventListenerObject[]>} Event listeners */
		$$l = {};
		/** @type {Map<EventListenerOrEventListenerObject, Function>} Event listener unsubscribe functions */
		$$l_u = /* @__PURE__ */ new Map();
		/** @type {any} The managed render effect for reflecting attributes */
		$$me;
		/** @type {ShadowRoot | null} The ShadowRoot of the custom element */
		$$shadowRoot = null;
		/**
		* @param {*} $$componentCtor
		* @param {*} $$slots
		* @param {ShadowRootInit | undefined} shadow_root_init
		*/
		constructor($$componentCtor, $$slots, shadow_root_init) {
			super();
			this.$$ctor = $$componentCtor;
			this.$$s = $$slots;
			if (shadow_root_init) this.$$shadowRoot = this.attachShadow(shadow_root_init);
		}
		/**
		* @param {string} type
		* @param {EventListenerOrEventListenerObject} listener
		* @param {boolean | AddEventListenerOptions} [options]
		*/
		addEventListener(type, listener, options) {
			this.$$l[type] = this.$$l[type] || [];
			this.$$l[type].push(listener);
			if (this.$$c) {
				const unsub = this.$$c.$on(type, listener);
				this.$$l_u.set(listener, unsub);
			}
			super.addEventListener(type, listener, options);
		}
		/**
		* @param {string} type
		* @param {EventListenerOrEventListenerObject} listener
		* @param {boolean | AddEventListenerOptions} [options]
		*/
		removeEventListener(type, listener, options) {
			super.removeEventListener(type, listener, options);
			if (this.$$c) {
				const unsub = this.$$l_u.get(listener);
				if (unsub) {
					unsub();
					this.$$l_u.delete(listener);
				}
			}
		}
		async connectedCallback() {
			this.$$cn = true;
			if (!this.$$c) {
				await Promise.resolve();
				if (!this.$$cn || this.$$c) return;
				/** @param {string} name */
				function create_slot(name) {
					/**
					* @param {Element} anchor
					*/
					return (anchor) => {
						const slot = create_element("slot");
						if (name !== "default") slot.name = name;
						append(anchor, slot);
					};
				}
				/** @type {Record<string, any>} */
				const $$slots = {};
				const existing_slots = get_custom_elements_slots(this);
				for (const name of this.$$s) if (name in existing_slots) if (name === "default" && !this.$$d.children) {
					this.$$d.children = create_slot(name);
					$$slots.default = true;
				} else $$slots[name] = create_slot(name);
				for (const attribute of this.attributes) {
					const name = this.$$g_p(attribute.name);
					if (!(name in this.$$d)) this.$$d[name] = get_custom_element_value(name, attribute.value, this.$$p_d, "toProp");
				}
				for (const key in this.$$p_d) if (!(key in this.$$d) && this[key] !== void 0) {
					this.$$d[key] = this[key];
					delete this[key];
				}
				this.$$c = createClassComponent({
					component: this.$$ctor,
					target: this.$$shadowRoot || this,
					props: {
						...this.$$d,
						$$slots,
						$$host: this
					}
				});
				this.$$me = effect_root(() => {
					render_effect(() => {
						this.$$r = true;
						for (const key of object_keys(this.$$c)) {
							if (!this.$$p_d[key]?.reflect) continue;
							this.$$d[key] = this.$$c[key];
							const attribute_value = get_custom_element_value(key, this.$$d[key], this.$$p_d, "toAttribute");
							if (attribute_value == null) this.removeAttribute(this.$$p_d[key].attribute || key);
							else this.setAttribute(this.$$p_d[key].attribute || key, attribute_value);
						}
						this.$$r = false;
					});
				});
				for (const type in this.$$l) for (const listener of this.$$l[type]) {
					const unsub = this.$$c.$on(type, listener);
					this.$$l_u.set(listener, unsub);
				}
				this.$$l = {};
			}
		}
		/**
		* @param {string} attr
		* @param {string} _oldValue
		* @param {string} newValue
		*/
		attributeChangedCallback(attr, _oldValue, newValue) {
			if (this.$$r) return;
			attr = this.$$g_p(attr);
			this.$$d[attr] = get_custom_element_value(attr, newValue, this.$$p_d, "toProp");
			this.$$c?.$set({ [attr]: this.$$d[attr] });
		}
		disconnectedCallback() {
			this.$$cn = false;
			Promise.resolve().then(() => {
				if (!this.$$cn && this.$$c) {
					this.$$c.$destroy();
					this.$$me();
					this.$$c = void 0;
				}
			});
		}
		/**
		* @param {string} attribute_name
		*/
		$$g_p(attribute_name) {
			return object_keys(this.$$p_d).find((key) => this.$$p_d[key].attribute === attribute_name || !this.$$p_d[key].attribute && key.toLowerCase() === attribute_name) || attribute_name;
		}
	};
	/**
	* @param {string} prop
	* @param {any} value
	* @param {Record<string, CustomElementPropDefinition>} props_definition
	* @param {'toAttribute' | 'toProp'} [transform]
	*/
	function get_custom_element_value(prop, value, props_definition, transform) {
		const type = props_definition[prop]?.type;
		value = type === "Boolean" && typeof value !== "boolean" ? value != null : value;
		if (!transform || !props_definition[prop]) return value;
		else if (transform === "toAttribute") switch (type) {
			case "Object":
			case "Array": return value == null ? null : JSON.stringify(value);
			case "Boolean": return value ? "" : null;
			case "Number": return value == null ? null : value;
			default: return value;
		}
		else switch (type) {
			case "Object":
			case "Array": return value && JSON.parse(value);
			case "Boolean": return value;
			case "Number": return value != null ? +value : value;
			default: return value;
		}
	}
	/**
	* @param {HTMLElement} element
	*/
	function get_custom_elements_slots(element) {
		/** @type {Record<string, true>} */
		const result = {};
		element.childNodes.forEach((node) => {
			result[node.slot || "default"] = true;
		});
		return result;
	}
	/**
	* @internal
	*
	* Turn a Svelte component into a custom element.
	* @param {any} Component  A Svelte component function
	* @param {Record<string, CustomElementPropDefinition>} props_definition  The props to observe
	* @param {string[]} slots  The slots to create
	* @param {string[]} exports  Explicitly exported values, other than props
	* @param {ShadowRootInit | undefined} shadow_root_init  Options passed to shadow DOM constructor
	* @param {(ce: new () => HTMLElement) => new () => HTMLElement} [extend]
	*/
	function create_custom_element(Component, props_definition, slots, exports, shadow_root_init, extend) {
		let Class = class extends SvelteElement {
			constructor() {
				super(Component, slots, shadow_root_init);
				this.$$p_d = props_definition;
			}
			static get observedAttributes() {
				return object_keys(props_definition).map((key) => (props_definition[key].attribute || key).toLowerCase());
			}
		};
		object_keys(props_definition).forEach((prop) => {
			define_property(Class.prototype, prop, {
				get() {
					return this.$$c && prop in this.$$c ? this.$$c[prop] : this.$$d[prop];
				},
				set(value) {
					value = get_custom_element_value(prop, value, props_definition);
					this.$$d[prop] = value;
					var component = this.$$c;
					if (component) if (get_descriptor(component, prop)?.get) component[prop] = value;
					else component.$set({ [prop]: value });
				}
			});
		});
		exports.forEach((property) => {
			define_property(Class.prototype, property, { get() {
				return this.$$c?.[property];
			} });
		});
		if (extend) Class = extend(Class);
		Component.element = Class;
		return Class;
	}
	//#endregion
	//#region src/util.js
	/** @type {Map<string, {ajaxId: string, regionId: string}>} */
	var instances = /* @__PURE__ */ new Map();
	var _currentRegionId = "";
	function getLogPrefix(pRegionId) {
		return `[uc-apex-chat] #${pRegionId || _currentRegionId} |`;
	}
	function initInstance(pRegionId, pAjaxId) {
		_currentRegionId = pRegionId;
		instances.set(pRegionId, {
			ajaxId: pAjaxId,
			regionId: pRegionId
		});
		debugTrace("initInstance", {
			pRegionId,
			pAjaxId
		});
	}
	function debugInfo(...params) {
		apex.debug.info(getLogPrefix(), ...params);
	}
	function debugTrace(...params) {
		apex.debug.trace(getLogPrefix(), ...params);
	}
	function debugError(...params) {
		apex.debug.error(getLogPrefix(), ...params);
	}
	function getInstanceAjaxId(pRegionId) {
		return instances.get(pRegionId || _currentRegionId)?.ajaxId || "";
	}
	function pluginAjax({ method, x2, x3, x4, x5, regionId }) {
		let ajaxId = getInstanceAjaxId(regionId);
		debugTrace("pluginAjax", {
			method,
			x2,
			x3,
			x4,
			x5,
			ajaxId,
			regionId
		});
		if (!ajaxId) throw new Error("ajaxId not set");
		return new Promise((resolve, reject) => {
			apex.server.plugin(ajaxId, {
				x01: method,
				x02: x2,
				x03: x3,
				x04: x4,
				x05: x5
			}, {
				success(data) {
					debugInfo("pluginAjax success", data);
					resolve(data);
				},
				error(err) {
					debugError(JSON.stringify(err));
					reject(err);
				},
				dataType: "json"
			});
		});
	}
	function fetchChats({ offset, regionId }) {
		debugTrace("fetchChats called", { offset });
		return pluginAjax({
			method: "FETCH_CHATS",
			x2: offset,
			regionId
		});
	}
	/**
	*
	* @param {fetchMessagesParams} params
	* @returns {Promise<fetchMessagesReturn>}
	*/
	function fetchMessages({ roomId, lastMessageId, olderOrNewer, regionId }) {
		debugTrace("fetchMessages called", {
			roomId,
			lastMessageId,
			olderOrNewer
		});
		return pluginAjax({
			method: "FETCH_MESSAGES",
			x2: roomId,
			x3: lastMessageId,
			x4: olderOrNewer,
			regionId
		});
	}
	function getSince(date) {
		const diffInSeconds = Math.floor((/* @__PURE__ */ new Date() - date) / 1e3);
		const intervals = [
			{
				label: "yr",
				seconds: 31536e3
			},
			{
				label: "mo",
				seconds: 2592e3
			},
			{
				label: "wk",
				seconds: 604800
			},
			{
				label: "d",
				seconds: 86400
			},
			{
				label: "hr",
				seconds: 3600
			},
			{
				label: "min",
				seconds: 60
			},
			{
				label: "sec",
				seconds: 1
			}
		];
		for (let i = 0; i < intervals.length; i++) {
			const interval = intervals[i];
			const count = Math.floor(diffInSeconds / interval.seconds);
			if (count >= 1) return `${count}${interval.label}${count > 1 ? "s" : ""}`;
		}
		return "just now";
	}
	var dateOptions = {
		year: "numeric",
		month: "short",
		day: "numeric"
	};
	var locale = navigator.language || navigator.userLanguage || "en-US";
	function formatDateString(timestamp) {
		return new Date(timestamp).toLocaleDateString(locale, dateOptions);
	}
	var timeOptions = {
		hour: "2-digit",
		minute: "2-digit"
	};
	function formatTimeString(timestamp) {
		return new Date(timestamp).toLocaleTimeString(locale, timeOptions);
	}
	function isDifferentDay(date1Str, date2Str) {
		const d1 = new Date(date1Str);
		const d2 = new Date(date2Str);
		return d1.toDateString() !== d2.toDateString();
	}
	/**
	*
	* @param {sendMessageParams} params
	* @returns {Promise<fetchMessagesReturn>}
	*/
	function sendMessage({ roomId, messageText, regionId }) {
		debugTrace("sendMessage called", {
			roomId,
			messageText
		});
		return pluginAjax({
			method: "SEND_MESSAGE",
			x2: roomId,
			x3: messageText,
			regionId
		});
	}
	async function createRoomAndSendMessage({ userIds, messageText, regionId }) {
		debugTrace("createRoomAndSendMessage called", {
			userIds,
			messageText
		});
		if (!userIds || !Array.isArray(userIds) || userIds.length === 0) throw new Error("Cannot create room with no users");
		if (!messageText) throw new Error("Cannot send message with no text");
		return (await pluginAjax({
			method: "CREATE_ROOM_AND_SEND_MESSAGE",
			x2: userIds.join(":"),
			x3: messageText,
			regionId
		})).roomId;
	}
	/**
	*
	* @param {getUserListParams} params
	* @returns {Promise<fetchUserListReturn>}
	*/
	function getUserList({ offset, search, regionId }) {
		debugTrace("getUserList called", {
			offset,
			search
		});
		return pluginAjax({
			method: "USER_LIST",
			x2: offset,
			x3: search,
			regionId
		});
	}
	/**
	*
	* @param {createGroupParams} params
	* @returns {number} roomId
	*/
	async function createGroup({ groupName, userIds, regionId }) {
		debugTrace("createGroup called", {
			groupName,
			userIds
		});
		return (await pluginAjax({
			method: "CREATE_GROUP",
			x2: groupName,
			x3: userIds.join(":"),
			regionId
		})).roomId;
	}
	function triggerEvent(eventName, data, regionId) {
		debugTrace("triggerEvent called", {
			eventName,
			data,
			regionId
		});
		apex.event.trigger(`#${regionId || _currentRegionId}`, eventName, data);
	}
	/**
	* @param {aiSendMessageParams} params
	* @returns {Promise<aiSendMessageReturn>}
	*/
	function aiSendMessage({ sessionId, messageText, agentCode, agentVersion, regionId }) {
		debugTrace("aiSendMessage called", {
			sessionId,
			messageText,
			agentCode,
			agentVersion
		});
		return pluginAjax({
			method: "AI_SEND_MESSAGE",
			x2: sessionId,
			x3: messageText,
			x4: agentCode,
			x5: agentVersion != null ? String(agentVersion) : "",
			regionId
		});
	}
	/**
	* @param {aiGetMessagesParams} params
	* @returns {Promise<aiGetMessagesReturn>}
	*/
	function aiGetMessages({ sessionId, lastMessageId, olderOrNewer, regionId }) {
		debugTrace("aiGetMessages called", {
			sessionId,
			lastMessageId,
			olderOrNewer
		});
		return pluginAjax({
			method: "AI_FETCH_MESSAGES",
			x2: sessionId,
			x3: lastMessageId != null ? String(lastMessageId) : "",
			x4: olderOrNewer || "older",
			regionId
		});
	}
	/**
	* Cooperatively cancel an in-flight AI turn.
	* @param {aiCancelParams} params
	* @returns {Promise<aiCancelReturn>}
	*/
	function aiCancel({ sessionId, userMessageId, regionId }) {
		debugTrace("aiCancel called", {
			sessionId,
			userMessageId
		});
		return pluginAjax({
			method: "AI_CANCEL",
			x2: sessionId,
			x3: userMessageId != null ? String(userMessageId) : "",
			regionId
		});
	}
	/**
	* Fetch developer debug details (agent config, session aggregates, latest
	* execution internals) for the current AI session. Gated server-side behind the
	* show_debug flag.
	* @param {aiExecDetailsParams} params
	* @returns {Promise<aiExecDetails>}
	*/
	function aiGetExecDetails({ sessionId, regionId }) {
		debugTrace("aiGetExecDetails called", { sessionId });
		return pluginAjax({
			method: "AI_EXEC_DETAILS",
			x2: sessionId,
			regionId
		});
	}
	/**
	* Persist a generated conversation title. The server write is write-once, so
	* the returned title may be an earlier one set by another tab.
	* @param {aiSetTitleParams} params
	* @returns {Promise<aiSetTitleReturn>}
	*/
	function aiSetTitle({ sessionId, title, regionId }) {
		debugTrace("aiSetTitle called", {
			sessionId,
			title
		});
		return pluginAjax({
			method: "AI_SET_TITLE",
			x2: sessionId,
			x3: title,
			regionId
		});
	}
	/**
	* Record the end user's verdict on a conversation. Unlike the title this is
	* deliberately overwritable, so it doubles as changing your mind; pass a null
	* rating to withdraw the feedback entirely. The response echoes the effective
	* value, which is empty when the core session header does not exist yet.
	* @param {aiSetFeedbackParams} params
	* @returns {Promise<aiSetFeedbackReturn>}
	*/
	function aiSetFeedback({ sessionId, rating, comment, regionId }) {
		debugTrace("aiSetFeedback called", {
			sessionId,
			rating
		});
		return pluginAjax({
			method: "AI_SET_FEEDBACK",
			x2: sessionId,
			x3: rating || "",
			x4: comment || "",
			regionId
		});
	}
	/**
	* @returns {Promise<aiNewSessionReturn>}
	*/
	function aiNewSession({ agentCode, agentVersion, regionId }) {
		debugTrace("aiNewSession called", {
			agentCode,
			agentVersion
		});
		return pluginAjax({
			method: "AI_NEW_SESSION",
			x2: agentCode,
			x3: agentVersion != null ? String(agentVersion) : "",
			regionId
		});
	}
	/**
	* @returns {Promise<{channels: channelObject[]}>}
	*/
	function fetchChannels({ regionId } = {}) {
		debugTrace("fetchChannels called");
		return pluginAjax({
			method: "FETCH_CHANNELS",
			regionId
		});
	}
	/**
	* @param {{ channelId: string, lastMessageId?: number, olderOrNewer?: string }} params
	* @returns {Promise<{messages: channelMessageObject[]}>}
	*/
	function fetchChannelMessages({ channelId, lastMessageId, olderOrNewer, regionId }) {
		debugTrace("fetchChannelMessages called", {
			channelId,
			lastMessageId,
			olderOrNewer
		});
		return pluginAjax({
			method: "FETCH_CHANNEL_MESSAGES",
			x2: channelId,
			x3: lastMessageId,
			x4: olderOrNewer,
			regionId
		});
	}
	/**
	* @param {{ channelId: string, messageText: string }} params
	* @returns {Promise<{messageId: number}>}
	*/
	function sendChannelMessage({ channelId, messageText, regionId }) {
		debugTrace("sendChannelMessage called", {
			channelId,
			messageText
		});
		return pluginAjax({
			method: "SEND_CHANNEL_MESSAGE",
			x2: channelId,
			x3: messageText,
			regionId
		});
	}
	/**
	* @param {{ channelId: string }} params
	*/
	function markChannelRead({ channelId, regionId }) {
		debugTrace("markChannelRead called", { channelId });
		return pluginAjax({
			method: "MARK_CHANNEL_READ",
			x2: channelId,
			regionId
		});
	}
	/**
	* @param {{ parentMessageId: number, lastMessageId?: number, olderOrNewer?: string }} params
	* @returns {Promise<{messages: channelMessageObject[]}>}
	*/
	function fetchThreadMessages({ parentMessageId, lastMessageId, olderOrNewer, regionId }) {
		debugTrace("fetchThreadMessages called", {
			parentMessageId,
			lastMessageId,
			olderOrNewer
		});
		return pluginAjax({
			method: "FETCH_THREAD_MESSAGES",
			x2: parentMessageId,
			x3: lastMessageId,
			x4: olderOrNewer,
			regionId
		});
	}
	/**
	* @param {{ channelId: string, parentMessageId: number, messageText: string }} params
	* @returns {Promise<{messageId: number}>}
	*/
	function sendThreadMessage({ channelId, parentMessageId, messageText, regionId }) {
		debugTrace("sendThreadMessage called", {
			channelId,
			parentMessageId,
			messageText
		});
		return pluginAjax({
			method: "SEND_THREAD_MESSAGE",
			x2: channelId,
			x3: parentMessageId,
			x4: messageText,
			regionId
		});
	}
	/**
	* @param {{ messageId: number, emoji: string }} params
	* @returns {Promise<{action: "added" | "removed"}>}
	*/
	function toggleReaction({ messageId, emoji, regionId }) {
		debugTrace("toggleReaction called", {
			messageId,
			emoji
		});
		return pluginAjax({
			method: "TOGGLE_REACTION",
			x2: messageId,
			x3: emoji,
			regionId
		});
	}
	//#endregion
	//#region src/ams.js
	/**
	* Initialize AMS
	* @param {string} amsUrl
	* @param {string} ajaxId
	* @param {string} username
	*/
	async function initAms(amsUrl, ajaxId, username) {
		if (window.uc?.chat?.initialized) {
			debugTrace("AMS already initialized", window.uc.chat);
			return;
		}
		if (!window.uc) window.uc = {};
		window.uc.chat = { initialized: true };
		debugTrace("initAms", {
			amsUrl,
			ajaxId,
			username
		});
		if (!amsUrl) {
			debugError("No AMS URL provided");
			return;
		}
		window.uc.ams.initConnection({
			url: amsUrl,
			ajaxIdentifier: ajaxId,
			username,
			session_id: apex.item("pInstance").getValue(),
			rooms: `UC-APEX-CHAT-${username}`,
			clientListenEventName: "uc.event",
			customEventHandler: (data) => {
				debugInfo("customEventHandler", data);
				apex.event.trigger(document, "uc-chat-new-message", data);
			}
		});
	}
	/**
	* Join additional AMS rooms after initial connection
	* @param {string[]} rooms - Room names to join
	*/
	function joinAmsRooms(rooms) {
		if (!window.uc?.ams?.joinRooms) {
			debugError("joinAmsRooms: AMS not initialized");
			return;
		}
		debugTrace("joinAmsRooms", rooms);
		window.uc.ams.joinRooms(rooms);
	}
	//#endregion
	//#region src/Spinner.svelte
	var root$20 = /* @__PURE__ */ from_html(`<div class="uc-chat-message-loader svelte-gp4vwo" role="status" aria-label="Loading"><div class="margin-right-sm" style="height: 1em; width: 1em;" aria-hidden="true"></div> <div>Loading</div></div>`);
	var $$css$23 = {
		hash: "svelte-gp4vwo",
		code: ".uc-chat-message-loader.svelte-gp4vwo {margin:var(--uc-chat-space-2) 0;display:flex;place-content:center;gap:var(--uc-chat-space-1);font-size:0.85em;color:var(--uc-chat-component-text-muted-color);}.uc-chat-message-loader .u-Processing {scale:0.6;}.uc-chat-message-loader .u-Processing.rendered {margin-top:0.6em;}"
	};
	function Spinner($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css$23);
		let spinnerTarget = /* @__PURE__ */ state(void 0);
		let lSpinner;
		onMount(() => {
			lSpinner = apex.util.showSpinner(get(spinnerTarget));
			lSpinner[0].classList.add("rendered");
		});
		onDestroy(() => {
			if (lSpinner) lSpinner.remove();
		});
		var div = root$20();
		bind_this(child(div), ($$value) => set(spinnerTarget, $$value), () => get(spinnerTarget));
		next(2);
		reset(div);
		append($$anchor, div);
		pop();
	}
	create_custom_element(Spinner, {}, [], [], { mode: "open" });
	//#endregion
	//#region src/AiDebugDialog.svelte
	var root_2$20 = /* @__PURE__ */ from_html(`<div class="uc-ai-debug-error svelte-w40hu0" role="alert"><span aria-hidden="true" class="fa fa-exclamation-triangle"></span> <p>Could not load debug details.</p> <button type="button" class="t-Button t-Button--small">Retry</button></div>`);
	var root_3$14 = /* @__PURE__ */ from_html(`<p class="uc-ai-debug-muted svelte-w40hu0">Debug details are disabled for this region.</p>`);
	var root_5$7 = /* @__PURE__ */ from_html(`<div class="uc-ai-debug-error-box svelte-w40hu0" role="alert"><div class="uc-ai-debug-error-title svelte-w40hu0"><span aria-hidden="true" class="fa fa-exclamation-triangle"></span> Turn failed</div> <pre class="svelte-w40hu0"> </pre></div>`);
	var root_6$5 = /* @__PURE__ */ from_html(`<section class="uc-ai-debug-section svelte-w40hu0"><h3 class="svelte-w40hu0">Session</h3> <dl class="uc-ai-debug-grid svelte-w40hu0"><dt class="svelte-w40hu0">Session ID</dt><dd class="uc-ai-debug-mono svelte-w40hu0"> </dd> <dt class="svelte-w40hu0">Status</dt><dd class="svelte-w40hu0"> </dd> <dt class="svelte-w40hu0">Turns</dt><dd class="svelte-w40hu0"> </dd> <dt class="svelte-w40hu0">Messages</dt><dd class="svelte-w40hu0"> </dd> <dt class="svelte-w40hu0">Tokens</dt> <dd class="svelte-w40hu0"> </dd> <dt class="svelte-w40hu0">Started</dt><dd class="svelte-w40hu0"> </dd> <dt class="svelte-w40hu0">Last activity</dt><dd class="svelte-w40hu0"> </dd></dl></section>`);
	var root_8$2 = /* @__PURE__ */ from_html(`<dt class="svelte-w40hu0">Duration</dt><dd class="svelte-w40hu0"> </dd>`, 1);
	var root_9$1 = /* @__PURE__ */ from_html(`<dt class="svelte-w40hu0">Error</dt><dd class="uc-ai-debug-err svelte-w40hu0"> </dd>`, 1);
	var root_7$4 = /* @__PURE__ */ from_html(`<dl class="uc-ai-debug-grid svelte-w40hu0"><dt class="svelte-w40hu0">Execution ID</dt><dd class="uc-ai-debug-mono svelte-w40hu0"> </dd> <dt class="svelte-w40hu0">Status</dt><dd class="svelte-w40hu0"> </dd> <dt class="svelte-w40hu0">Iterations</dt><dd class="svelte-w40hu0"> </dd> <dt class="svelte-w40hu0">Tool calls</dt><dd class="svelte-w40hu0"> </dd> <dt class="svelte-w40hu0">Tokens</dt> <dd class="svelte-w40hu0"> </dd> <dt class="svelte-w40hu0">Started</dt><dd class="svelte-w40hu0"> </dd> <dt class="svelte-w40hu0">Completed</dt><dd class="svelte-w40hu0"> </dd> <!> <!></dl>`);
	var root_10$2 = /* @__PURE__ */ from_html(`<p class="uc-ai-debug-muted svelte-w40hu0">No completed turn yet.</p>`);
	var root_13$1 = /* @__PURE__ */ from_html(`<details class="uc-ai-debug-raw svelte-w40hu0"><summary class="svelte-w40hu0"><span class="svelte-w40hu0"> </span> <button type="button" class="uc-ai-debug-copy svelte-w40hu0"><span aria-hidden="true"></span></button></summary> <pre class="svelte-w40hu0"><code> </code></pre></details>`);
	var root_11$1 = /* @__PURE__ */ from_html(`<section class="uc-ai-debug-section svelte-w40hu0"><h3 class="svelte-w40hu0">Raw</h3> <!></section>`);
	var root_4$8 = /* @__PURE__ */ from_html(`<!> <section class="uc-ai-debug-section svelte-w40hu0"><h3 class="svelte-w40hu0">Agent</h3> <dl class="uc-ai-debug-grid svelte-w40hu0"><dt class="svelte-w40hu0">Code</dt><dd class="svelte-w40hu0"> </dd> <dt class="svelte-w40hu0">Version</dt><dd class="svelte-w40hu0"> </dd> <dt class="svelte-w40hu0">Type</dt><dd class="svelte-w40hu0"> </dd></dl></section> <!> <section class="uc-ai-debug-section svelte-w40hu0"><h3 class="svelte-w40hu0">Latest execution</h3> <!></section> <!>`, 1);
	var root$19 = /* @__PURE__ */ from_html(`<dialog class="uc-ai-debug-dialog svelte-w40hu0"><div class="uc-ai-debug-header svelte-w40hu0"><h2 class="uc-ai-debug-title svelte-w40hu0"><span aria-hidden="true" class="fa fa-bug"></span> Debug info</h2> <button type="button" class="t-Button t-Button--noLabel t-Button--icon t-Button--simple" title="Close" aria-label="Close"><span aria-hidden="true" class="t-Icon fa fa-close"></span></button></div> <div class="uc-ai-debug-body svelte-w40hu0"><!></div></dialog>`);
	var $$css$22 = {
		hash: "svelte-w40hu0",
		code: ".uc-ai-debug-dialog.svelte-w40hu0 {padding:0;border:1px solid var(--uc-chat-component-border-color);width:90vw;max-width:34em;max-height:80vh;background:var(--uc-chat-component-background-color);color:var(--uc-chat-component-text-title-color);border-radius:var(--uc-chat-component-border-radius);box-shadow:var(--uc-chat-shadow-md), var(--uc-chat-shadow-sm);outline:none;font-family:var(--uc-chat-font-base);overflow:hidden;}.uc-ai-debug-dialog.svelte-w40hu0::backdrop {background-color:var(--jui-overlay-background-color, rgba(0, 0, 0, 0.25));}.uc-ai-debug-dialog.svelte-w40hu0,\n  .uc-ai-debug-dialog.svelte-w40hu0::backdrop {transition:display 0.2s allow-discrete,\n      overlay 0.2s allow-discrete,\n      opacity 0.2s;opacity:0;}.uc-ai-debug-dialog[open].svelte-w40hu0 {opacity:1;display:flex;flex-direction:column;&::backdrop {opacity:1;}}\n\n  @starting-style {.uc-ai-debug-dialog[open].svelte-w40hu0,\n    .uc-ai-debug-dialog[open].svelte-w40hu0::backdrop {opacity:0;}\n  }\n\n  @media (prefers-reduced-motion) {.uc-ai-debug-dialog.svelte-w40hu0,\n    .uc-ai-debug-dialog.svelte-w40hu0::backdrop {transition:none;}\n  }.uc-ai-debug-header.svelte-w40hu0 {display:flex;align-items:center;justify-content:space-between;padding:0.5em 0.75em;border-bottom:1px solid var(--uc-chat-component-border-color);flex:0 0 auto;}.uc-ai-debug-title.svelte-w40hu0 {margin:0;font-size:1.05em;font-weight:500;display:flex;align-items:center;gap:0.5em;color:var(--uc-chat-component-text-title-color);}.uc-ai-debug-body.svelte-w40hu0 {padding:0.75em;overflow-y:auto;min-height:0;}.uc-ai-debug-section.svelte-w40hu0 {margin-bottom:1em;}.uc-ai-debug-section.svelte-w40hu0:last-child {margin-bottom:0;}.uc-ai-debug-section.svelte-w40hu0 > h3:where(.svelte-w40hu0) {margin:0 0 0.4em;font-size:0.75em;font-weight:600;text-transform:uppercase;letter-spacing:0.05em;color:var(--uc-chat-component-text-muted-color);}.uc-ai-debug-grid.svelte-w40hu0 {display:grid;grid-template-columns:minmax(6em, auto) 1fr;gap:0.25em 0.75em;margin:0;font-size:0.85em;}.uc-ai-debug-grid.svelte-w40hu0 > dt:where(.svelte-w40hu0) {color:var(--uc-chat-component-text-muted-color);font-weight:400;}.uc-ai-debug-grid.svelte-w40hu0 > dd:where(.svelte-w40hu0) {margin:0;word-break:break-word;color:var(--uc-chat-component-text-title-color);}.uc-ai-debug-mono.svelte-w40hu0 {font-family:ui-monospace, \"SF Mono\", Menlo, Consolas, monospace;font-size:0.95em;}.uc-ai-debug-err.svelte-w40hu0 {color:var(--uc-chat-danger-color, #c62828);}.uc-ai-debug-error-box.svelte-w40hu0 {margin-bottom:1em;border:1px solid var(--uc-chat-danger-color, #c62828);border-left:3px solid var(--uc-chat-danger-color, #c62828);border-radius:0.4em;background-color:rgba(198, 40, 40, 0.06);}.uc-ai-debug-error-title.svelte-w40hu0 {display:flex;align-items:center;gap:0.4em;padding:0.4em 0.6em;font-weight:600;font-size:0.85em;color:var(--uc-chat-danger-color, #c62828);}.uc-ai-debug-error-box.svelte-w40hu0 pre:where(.svelte-w40hu0) {margin:0;padding:0 0.6em 0.6em;white-space:pre-wrap;word-break:break-word;font-size:0.85em;line-height:1.45;color:var(--uc-chat-component-text-title-color);}.uc-ai-debug-muted.svelte-w40hu0 {margin:0;font-size:0.85em;color:var(--uc-chat-component-text-muted-color);}.uc-ai-debug-error.svelte-w40hu0 {display:flex;flex-direction:column;align-items:center;gap:0.5em;padding:1em;color:var(--uc-chat-component-text-muted-color);}.uc-ai-debug-raw.svelte-w40hu0 {border:1px solid var(--uc-chat-component-border-color);border-radius:0.4em;margin-bottom:0.4em;font-size:0.85em;}.uc-ai-debug-raw.svelte-w40hu0 > summary:where(.svelte-w40hu0) {display:flex;align-items:center;justify-content:space-between;gap:0.5em;cursor:pointer;padding:0.4em 0.6em;list-style:none;user-select:none;color:var(--uc-chat-component-text-muted-color);font-weight:500;}.uc-ai-debug-raw.svelte-w40hu0 > summary:where(.svelte-w40hu0)::-webkit-details-marker {display:none;}.uc-ai-debug-raw.svelte-w40hu0 > summary:where(.svelte-w40hu0)::before {content:\"\\25B6\";font-size:0.7em;transition:transform 0.15s;flex-shrink:0;margin-right:0.25em;}.uc-ai-debug-raw[open].svelte-w40hu0 > summary:where(.svelte-w40hu0)::before {transform:rotate(90deg);}.uc-ai-debug-raw.svelte-w40hu0 > summary:where(.svelte-w40hu0) > span:where(.svelte-w40hu0):first-of-type {flex:1;}.uc-ai-debug-copy.svelte-w40hu0 {border:none;background:transparent;color:var(--uc-chat-component-text-muted-color);cursor:pointer;padding:0 0.25em;font-size:1em;}.uc-ai-debug-raw.svelte-w40hu0 pre:where(.svelte-w40hu0) {margin:0;padding:0.5em 0.6em;background-color:var(--uc-chat-footer-background-color);overflow-x:auto;font-size:0.95em;line-height:1.45;border-top:1px solid var(--uc-chat-component-border-color);}"
	};
	function AiDebugDialog($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css$22);
		let regionId = prop($$props, "regionId", 7), sessionId = prop($$props, "sessionId", 7), agentCode = prop($$props, "agentCode", 7), agentVersion = prop($$props, "agentVersion", 7);
		let dialog = /* @__PURE__ */ state(void 0);
		let loading = /* @__PURE__ */ state(false);
		let loadError = /* @__PURE__ */ state(false);
		/** @type {import("./typedef").aiExecDetails | null} */
		let details = /* @__PURE__ */ state(null);
		let copiedKey = /* @__PURE__ */ state("");
		let copyTimer = null;
		function open() {
			get(dialog)?.showModal();
			load();
		}
		function close() {
			get(dialog)?.close();
		}
		async function load() {
			if (!sessionId()) {
				set(details, {
					enabled: true,
					agent: {
						code: agentCode(),
						version: agentVersion()
					}
				}, true);
				return;
			}
			set(loadError, false);
			set(loading, true);
			try {
				set(details, await aiGetExecDetails({
					sessionId: sessionId(),
					regionId: regionId()
				}), true);
			} catch (e) {
				debugError("AiDebugDialog fetch failed", e);
				set(loadError, true);
			} finally {
				set(loading, false);
			}
		}
		function retry() {
			load();
		}
		let duration = /* @__PURE__ */ user_derived(() => {
			let s = get(details)?.execution?.startedAt;
			let c = get(details)?.execution?.completedAt;
			if (!s || !c) return "";
			let ms = new Date(c).getTime() - new Date(s).getTime();
			if (Number.isNaN(ms) || ms < 0) return "";
			let secs = Math.round(ms / 1e3);
			if (secs < 60) return `${secs}s`;
			return `${Math.floor(secs / 60)}m ${secs % 60}s`;
		});
		function formatTs(ts) {
			if (!ts) return "—";
			return ts.replace("T", " ");
		}
		function num(n) {
			return n == null ? "—" : n;
		}
		function str(s) {
			return s == null || s === "" ? "—" : s;
		}
		function formatJson(s) {
			if (!s) return "";
			try {
				return JSON.stringify(JSON.parse(s), null, 2);
			} catch {
				return s;
			}
		}
		async function copy(key, value) {
			try {
				await navigator.clipboard.writeText(value ?? "");
				set(copiedKey, key, true);
				clearTimeout(copyTimer);
				copyTimer = setTimeout(() => {
					set(copiedKey, "");
				}, 1500);
			} catch (e) {
				debugError("AiDebugDialog copy failed", e);
			}
		}
		let rawEntries = /* @__PURE__ */ user_derived(() => [
			{
				key: "inputParameters",
				label: "Input parameters",
				value: get(details)?.raw?.inputParameters
			},
			{
				key: "outputResult",
				label: "Output result",
				value: get(details)?.raw?.outputResult
			},
			{
				key: "envContext",
				label: "Environment context",
				value: get(details)?.raw?.envContext
			}
		]);
		var $$exports = {
			open,
			get regionId() {
				return regionId();
			},
			set regionId($$value) {
				regionId($$value);
				flushSync();
			},
			get sessionId() {
				return sessionId();
			},
			set sessionId($$value) {
				sessionId($$value);
				flushSync();
			},
			get agentCode() {
				return agentCode();
			},
			set agentCode($$value) {
				agentCode($$value);
				flushSync();
			},
			get agentVersion() {
				return agentVersion();
			},
			set agentVersion($$value) {
				agentVersion($$value);
				flushSync();
			}
		};
		var dialog_1 = root$19();
		var div = child(dialog_1);
		var button = sibling(child(div), 2);
		reset(div);
		var div_1 = sibling(div, 2);
		var node = child(div_1);
		var consequent = ($$anchor) => {
			Spinner($$anchor, {});
		};
		var consequent_1 = ($$anchor) => {
			var div_2 = root_2$20();
			var button_1 = sibling(child(div_2), 4);
			reset(div_2);
			delegated("click", button_1, retry);
			append($$anchor, div_2);
		};
		var consequent_2 = ($$anchor) => {
			append($$anchor, root_3$14());
		};
		var consequent_10 = ($$anchor) => {
			var fragment_1 = root_4$8();
			var node_1 = first_child(fragment_1);
			var consequent_3 = ($$anchor) => {
				var div_3 = root_5$7();
				var pre = sibling(child(div_3), 2);
				var text = child(pre, true);
				reset(pre);
				reset(div_3);
				template_effect(() => set_text(text, get(details).turnError || get(details).execution?.errorMessage));
				append($$anchor, div_3);
			};
			if_block(node_1, ($$render) => {
				if (get(details).turnError || get(details).execution?.errorMessage) $$render(consequent_3);
			});
			var section = sibling(node_1, 2);
			var dl = sibling(child(section), 2);
			var dd = sibling(child(dl));
			var text_1 = child(dd, true);
			reset(dd);
			var dd_1 = sibling(dd, 3);
			var text_2 = child(dd_1, true);
			reset(dd_1);
			var dd_2 = sibling(dd_1, 3);
			var text_3 = child(dd_2, true);
			reset(dd_2);
			reset(dl);
			reset(section);
			var node_2 = sibling(section, 2);
			var consequent_4 = ($$anchor) => {
				var section_1 = root_6$5();
				var dl_1 = sibling(child(section_1), 2);
				var dd_3 = sibling(child(dl_1));
				var text_4 = child(dd_3, true);
				reset(dd_3);
				var dd_4 = sibling(dd_3, 3);
				var text_5 = child(dd_4, true);
				reset(dd_4);
				var dd_5 = sibling(dd_4, 3);
				var text_6 = child(dd_5, true);
				reset(dd_5);
				var dd_6 = sibling(dd_5, 3);
				var text_7 = child(dd_6, true);
				reset(dd_6);
				var dd_7 = sibling(dd_6, 4);
				var text_8 = child(dd_7);
				reset(dd_7);
				var dd_8 = sibling(dd_7, 3);
				var text_9 = child(dd_8, true);
				reset(dd_8);
				var dd_9 = sibling(dd_8, 3);
				var text_10 = child(dd_9, true);
				reset(dd_9);
				reset(dl_1);
				reset(section_1);
				template_effect(($0, $1, $2, $3, $4, $5, $6, $7) => {
					set_text(text_4, $0);
					set_text(text_5, $1);
					set_text(text_6, $2);
					set_text(text_7, $3);
					set_text(text_8, `${$4 ?? ""} in / ${$5 ?? ""} out`);
					set_text(text_9, $6);
					set_text(text_10, $7);
				}, [
					() => str(get(details).session.sessionId),
					() => str(get(details).session.status),
					() => num(get(details).session.turnCount),
					() => num(get(details).session.messageCount),
					() => num(get(details).session.totalInputTokens),
					() => num(get(details).session.totalOutputTokens),
					() => formatTs(get(details).session.startedAt),
					() => formatTs(get(details).session.lastActivityAt)
				]);
				append($$anchor, section_1);
			};
			if_block(node_2, ($$render) => {
				if (get(details).session) $$render(consequent_4);
			});
			var section_2 = sibling(node_2, 2);
			var node_3 = sibling(child(section_2), 2);
			var consequent_7 = ($$anchor) => {
				var dl_2 = root_7$4();
				var dd_10 = sibling(child(dl_2));
				var text_11 = child(dd_10, true);
				reset(dd_10);
				var dd_11 = sibling(dd_10, 3);
				var text_12 = child(dd_11, true);
				reset(dd_11);
				var dd_12 = sibling(dd_11, 3);
				var text_13 = child(dd_12, true);
				reset(dd_12);
				var dd_13 = sibling(dd_12, 3);
				var text_14 = child(dd_13, true);
				reset(dd_13);
				var dd_14 = sibling(dd_13, 4);
				var text_15 = child(dd_14);
				reset(dd_14);
				var dd_15 = sibling(dd_14, 3);
				var text_16 = child(dd_15, true);
				reset(dd_15);
				var dd_16 = sibling(dd_15, 3);
				var text_17 = child(dd_16, true);
				reset(dd_16);
				var node_4 = sibling(dd_16, 2);
				var consequent_5 = ($$anchor) => {
					var fragment_2 = root_8$2();
					var dd_17 = sibling(first_child(fragment_2));
					var text_18 = child(dd_17, true);
					reset(dd_17);
					template_effect(() => set_text(text_18, get(duration)));
					append($$anchor, fragment_2);
				};
				if_block(node_4, ($$render) => {
					if (get(duration)) $$render(consequent_5);
				});
				var node_5 = sibling(node_4, 2);
				var consequent_6 = ($$anchor) => {
					var fragment_3 = root_9$1();
					var dd_18 = sibling(first_child(fragment_3));
					var text_19 = child(dd_18, true);
					reset(dd_18);
					template_effect(() => set_text(text_19, get(details).execution.errorMessage));
					append($$anchor, fragment_3);
				};
				if_block(node_5, ($$render) => {
					if (get(details).execution.errorMessage) $$render(consequent_6);
				});
				reset(dl_2);
				template_effect(($0, $1, $2, $3, $4, $5, $6, $7) => {
					set_text(text_11, $0);
					set_text(text_12, $1);
					set_text(text_13, $2);
					set_text(text_14, $3);
					set_text(text_15, `${$4 ?? ""} in / ${$5 ?? ""} out`);
					set_text(text_16, $6);
					set_text(text_17, $7);
				}, [
					() => num(get(details).execution.executionId),
					() => str(get(details).execution.status),
					() => num(get(details).execution.iterationCount),
					() => num(get(details).execution.toolCallsCount),
					() => num(get(details).execution.inputTokens),
					() => num(get(details).execution.outputTokens),
					() => formatTs(get(details).execution.startedAt),
					() => formatTs(get(details).execution.completedAt)
				]);
				append($$anchor, dl_2);
			};
			var alternate = ($$anchor) => {
				append($$anchor, root_10$2());
			};
			if_block(node_3, ($$render) => {
				if (get(details).execution) $$render(consequent_7);
				else $$render(alternate, -1);
			});
			reset(section_2);
			var node_6 = sibling(section_2, 2);
			var consequent_9 = ($$anchor) => {
				var section_3 = root_11$1();
				each(sibling(child(section_3), 2), 17, () => get(rawEntries), (entry) => entry.key, ($$anchor, entry) => {
					var fragment_4 = comment();
					var node_8 = first_child(fragment_4);
					var consequent_8 = ($$anchor) => {
						var details_1 = root_13$1();
						var summary = child(details_1);
						var span = child(summary);
						var text_20 = child(span, true);
						reset(span);
						var button_2 = sibling(span, 2);
						var span_1 = child(button_2);
						let classes;
						reset(button_2);
						reset(summary);
						var pre_1 = sibling(summary, 2);
						var code = child(pre_1);
						var text_21 = child(code, true);
						reset(code);
						reset(pre_1);
						reset(details_1);
						template_effect(($0) => {
							set_text(text_20, get(entry).label);
							set_attribute(button_2, "title", get(copiedKey) === get(entry).key ? "Copied" : "Copy");
							set_attribute(button_2, "aria-label", get(copiedKey) === get(entry).key ? "Copied" : "Copy");
							classes = set_class(span_1, 1, "fa", null, classes, {
								"fa-copy": get(copiedKey) !== get(entry).key,
								"fa-check": get(copiedKey) === get(entry).key
							});
							set_text(text_21, $0);
						}, [() => formatJson(get(entry).value)]);
						delegated("click", button_2, (e) => {
							e.preventDefault();
							copy(get(entry).key, formatJson(get(entry).value));
						});
						append($$anchor, details_1);
					};
					if_block(node_8, ($$render) => {
						if (get(entry).value) $$render(consequent_8);
					});
					append($$anchor, fragment_4);
				});
				reset(section_3);
				append($$anchor, section_3);
			};
			var d = /* @__PURE__ */ user_derived(() => get(rawEntries).some((r) => r.value));
			if_block(node_6, ($$render) => {
				if (get(d)) $$render(consequent_9);
			});
			template_effect(($0, $1, $2) => {
				set_text(text_1, $0);
				set_text(text_2, $1);
				set_text(text_3, $2);
			}, [
				() => str(get(details).agent?.code ?? agentCode()),
				() => str(get(details).agent?.version ?? agentVersion()),
				() => str(get(details).agent?.type)
			]);
			append($$anchor, fragment_1);
		};
		if_block(node, ($$render) => {
			if (get(loading)) $$render(consequent);
			else if (get(loadError)) $$render(consequent_1, 1);
			else if (get(details) && get(details).enabled === false) $$render(consequent_2, 2);
			else if (get(details)) $$render(consequent_10, 3);
		});
		reset(div_1);
		reset(dialog_1);
		bind_this(dialog_1, ($$value) => set(dialog, $$value), () => get(dialog));
		delegated("click", button, close);
		append($$anchor, dialog_1);
		return pop($$exports);
	}
	delegate(["click"]);
	create_custom_element(AiDebugDialog, {
		regionId: {},
		sessionId: {},
		agentCode: {},
		agentVersion: {}
	}, [], ["open"], { mode: "open" });
	//#endregion
	//#region src/constants.js
	var EVENT_MESSAGE_SENT = "uc_chat_aftersendmsg";
	var EVENT_RP_SHOW_CHAT = "right-pane-show-chat";
	var LP_MODE_CHATS = "chats";
	var LP_MODE_NEW_CHAT = "newChat";
	var RP_MODE_CHAT = "chat";
	var RP_MODE_NEW_GROUP = "newGroup";
	var EVENT_CHANNEL_MESSAGE_SENT = "uc_chat_channel_aftersendmsg";
	var AI_ROLE_USER = "user";
	var AI_ROLE_ASSISTANT = "assistant";
	var AI_ROLE_TOOL_RESULT = "tool_result";
	var AI_ROLE_TOOL_STEP = "tool_step";
	var GUARDRAIL_KIND_BUDGET = "budget";
	var GUARDRAIL_KIND_RATE = "rate";
	var GUARDRAIL_KIND_TOOL_RATE = "tool_rate";
	var GUARDRAIL_KIND_CONCURRENCY = "concurrency";
	var GUARDRAIL_HIT_MESSAGES = {
		[GUARDRAIL_KIND_BUDGET]: "The AI usage limit has been reached. Please try again later.",
		[GUARDRAIL_KIND_RATE]: "Too many AI requests have been made. Please wait a moment and try again.",
		[GUARDRAIL_KIND_TOOL_RATE]: "The AI stopped because it reached an activity limit. Please try again later.",
		[GUARDRAIL_KIND_CONCURRENCY]: "Too many AI requests are running at once. Please wait for them to finish."
	};
	var GUARDRAIL_HIT_FALLBACK = "This request could not be completed because an AI usage limit was reached.";
	var GUARDRAIL_WARN_MESSAGE = "You're close to the AI usage limit for this period.";
	/**
	* User-facing copy for a guardrail notice. An unknown kind (a newer backend
	* reporting a limit type this build predates) still produces a sensible
	* sentence rather than an empty banner.
	* @param {string} state GUARDRAIL_STATE_WARN | GUARDRAIL_STATE_HIT
	* @param {string} [kind] GUARDRAIL_KIND_*
	* @returns {string}
	*/
	function guardrailMessage(state, kind) {
		if (state === "warn") return GUARDRAIL_WARN_MESSAGE;
		return GUARDRAIL_HIT_MESSAGES[kind] || GUARDRAIL_HIT_FALLBACK;
	}
	var AI_CONTEXT_CONFLICT_MESSAGE = "This conversation is tied to different data than the page is showing now. Start a new chat to continue here.";
	var AI_ANIM_DOTS = "dots";
	var AI_ANIM_BRAILLE = "braille";
	var AI_ANIM_PLASMA = "plasma";
	var AI_ANIM_MATRIX = "matrix";
	var AI_ANIM_VARIANTS = [
		AI_ANIM_DOTS,
		AI_ANIM_BRAILLE,
		AI_ANIM_PLASMA,
		AI_ANIM_MATRIX
	];
	var AI_DETAIL_STATUS = "status";
	var AI_DETAIL_TOOLS = "tools";
	var AI_DETAIL_LEVELS = [
		"off",
		AI_DETAIL_STATUS,
		AI_DETAIL_TOOLS
	];
	var FEEDBACK_RATING_DOWN = "down";
	var FEEDBACK_COMMENT_MAX = 2e3;
	var FEEDBACK_UP_LABEL = "Good response";
	var FEEDBACK_DOWN_LABEL = "Bad response";
	var FEEDBACK_UP_LABEL_ACTIVE = "Good response — click to undo";
	var FEEDBACK_DOWN_LABEL_ACTIVE = "Bad response — click to undo";
	var FEEDBACK_COMMENT_PROMPT = "What went wrong? (optional)";
	var FEEDBACK_COMMENT_HINT = "Please don't include sensitive information.";
	var FEEDBACK_COMMENT_SEND = "Send";
	var FEEDBACK_COMMENT_SKIP = "Skip";
	var FEEDBACK_THANKS = "Thanks for the feedback.";
	//#endregion
	//#region src/AiGuardrailBanner.svelte
	var root$18 = /* @__PURE__ */ from_html(`<div><span aria-hidden="true"></span> <span class="uc-ai-guardrail-text svelte-s7otyc"> </span> <button type="button" class="t-Button t-Button--noLabel t-Button--icon t-Button--simple uc-ai-guardrail-close svelte-s7otyc" title="Dismiss" aria-label="Dismiss notice"><span aria-hidden="true" class="t-Icon fa fa-close"></span></button></div>`);
	var $$css$21 = {
		hash: "svelte-s7otyc",
		code: "\n  /* A coloured left rail is now unique to notices. It used to be shared with the\n     tool card, where it meant nothing in particular — so severity and \"this is a\n     tool\" looked like the same thing. */.uc-ai-guardrail.svelte-s7otyc {display:flex;align-items:center;gap:var(--uc-chat-space-2);flex:0 0 auto;padding:var(--uc-chat-space-2) var(--uc-chat-space-2)\n      var(--uc-chat-space-2) var(--uc-chat-space-3);font-size:0.85em;line-height:1.35;\n    /* Tint the theme's own warning colour into the surface rather than shipping\n       a hand-picked amber. The old #fff8e1 / #7a4f00 pair stayed cream-on-brown\n       in dark mode, where it was the brightest thing on the screen. Text keeps\n       the theme's text colour: --ut-palette-warning is #ffc628 in Vita and\n       would fail contrast as a foreground. */color:var(--uc-chat-component-text-title-color);background-color:color-mix(\n      in srgb,\n      var(--uc-chat-warning-color) 14%,\n      var(--uc-chat-surface-background-color)\n    );border-left:3px solid var(--uc-chat-warning-color);z-index:1;}.uc-ai-guardrail.svelte-s7otyc > .t-Icon:where(.svelte-s7otyc) {color:var(--uc-chat-warning-color);flex:0 0 auto;}\n\n  /* A hit is a refusal, not a caution — reuse the error colour already used for\n     failed turns so the two read as the same severity. */.uc-ai-guardrail.is-hit.svelte-s7otyc {background-color:color-mix(\n      in srgb,\n      var(--uc-chat-danger-color) 10%,\n      var(--uc-chat-surface-background-color)\n    );border-left-color:var(--uc-chat-danger-color);}.uc-ai-guardrail.is-hit.svelte-s7otyc > .t-Icon:where(.svelte-s7otyc) {color:var(--uc-chat-danger-color);}.uc-ai-guardrail-text.svelte-s7otyc {flex:1;min-width:0;}\n\n  /* An inline dismiss inside a tinted strip, not a toolbar button: t-Button--simple\n     still paints a border and a background, which read as a boxed X floating on\n     the tint. Strip the chrome, keep the hit area and the focus ring. */.uc-ai-guardrail-close.svelte-s7otyc {flex:0 0 auto;color:inherit;background-color:transparent;border-color:transparent;box-shadow:none;}.uc-ai-guardrail-close.svelte-s7otyc:hover {background-color:color-mix(\n      in srgb,\n      var(--uc-chat-component-text-title-color) 8%,\n      transparent\n    );border-color:transparent;}"
	};
	function AiGuardrailBanner($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css$21);
		/**
		* Guardrail notice strip, shown between the transcript and the composer.
		*
		* Lives outside the scrolling transcript on purpose: a governance notice stays
		* true until the period rolls over, so it must not scroll away like a message
		* bubble, and it must not become part of the conversation the agent sees.
		*
		* Copy comes from `guardrailMessage()` — this component never renders a limit
		* code, figure or percentage. A caller with copy of its own (the run-context
		* conflict notice) passes `text` instead of a kind; the strip is the same
		* shape, so two notices in the same slot never look like two components.
		*
		* @typedef {Object} Props
		* @property {string} state GUARDRAIL_STATE_WARN | GUARDRAIL_STATE_HIT
		* @property {string} [kind] GUARDRAIL_KIND_*
		* @property {string} [text] Copy to show instead of `guardrailMessage(state, kind)`
		* @property {() => void} onDismiss Called when the user closes the notice
		*/
		/** @type {Props} */
		let state = prop($$props, "state", 7), kind = prop($$props, "kind", 7), text = prop($$props, "text", 7), onDismiss = prop($$props, "onDismiss", 7);
		let isHit = /* @__PURE__ */ user_derived(() => state() === "hit");
		let message = /* @__PURE__ */ user_derived(() => text() || guardrailMessage(state(), kind()));
		var $$exports = {
			get state() {
				return state();
			},
			set state($$value) {
				state($$value);
				flushSync();
			},
			get kind() {
				return kind();
			},
			set kind($$value) {
				kind($$value);
				flushSync();
			},
			get text() {
				return text();
			},
			set text($$value) {
				text($$value);
				flushSync();
			},
			get onDismiss() {
				return onDismiss();
			},
			set onDismiss($$value) {
				onDismiss($$value);
				flushSync();
			}
		};
		var div = root$18();
		let classes;
		var span = child(div);
		var span_1 = sibling(span, 2);
		var text_1 = child(span_1, true);
		reset(span_1);
		var button = sibling(span_1, 2);
		reset(div);
		template_effect(() => {
			classes = set_class(div, 1, "uc-ai-guardrail svelte-s7otyc", null, classes, { "is-hit": get(isHit) });
			set_attribute(div, "role", get(isHit) ? "alert" : "status");
			set_class(span, 1, `t-Icon fa ${get(isHit) ? "fa-ban" : "fa-exclamation-triangle"}`, "svelte-s7otyc");
			set_text(text_1, get(message));
		});
		delegated("click", button, function(...$$args) {
			onDismiss()?.apply(this, $$args);
		});
		append($$anchor, div);
		return pop($$exports);
	}
	delegate(["click"]);
	create_custom_element(AiGuardrailBanner, {
		state: {},
		kind: {},
		text: {},
		onDismiss: {}
	}, [], [], { mode: "open" });
	//#endregion
	//#region src/AiFeedbackControl.svelte
	var root_1$15 = /* @__PURE__ */ from_html(`<span class="uc-ai-feedback-thanks svelte-1ramda1" role="status"> </span>`);
	var root_2$19 = /* @__PURE__ */ from_html(`<div class="uc-ai-feedback-panel svelte-1ramda1" role="none"><label class="uc-ai-feedback-label svelte-1ramda1"> </label> <textarea class="apex-item-textarea uc-ai-feedback-input svelte-1ramda1" rows="2"></textarea> <div class="uc-ai-feedback-panel-footer svelte-1ramda1"><span class="uc-ai-feedback-hint svelte-1ramda1"> </span> <button type="button" class="t-Button t-Button--small"> </button> <button type="button" class="t-Button t-Button--small t-Button--hot"> </button></div></div>`);
	var root$17 = /* @__PURE__ */ from_html(`<div class="uc-ai-feedback svelte-1ramda1"><span><button type="button"><span aria-hidden="true"></span></button> <button type="button"><span aria-hidden="true"></span></button> <!></span> <!></div>`);
	var $$css$20 = {
		hash: "svelte-1ramda1",
		code: "\n  /* The buttons belong to the meta row's flex layout and the panel needs a line\n     of its own, so the wrapper must not become a box between them. */.uc-ai-feedback.svelte-1ramda1 {display:contents;}.uc-ai-feedback-actions.svelte-1ramda1 {display:inline-flex;align-items:center;gap:0.15em;margin-left:calc(-1 * var(--uc-chat-space-1));\n    /* Hidden until the message is hovered, exactly like the copy button. */opacity:0;transition:opacity 0.15s;}\n\n  /* The hover trigger is the parent bubble, so the ancestor half of the selector\n     has to be :global — the parent's scope class is not on our elements. Every\n     reveal rule is kept here, and each is at least as specific as the base rule\n     above, so which component's stylesheet comes first cannot decide the outcome.\n     A verdict already given stays visible on mouse-out: a chosen state that\n     vanishes reads as a lost click. */.uc-ai-msg-assistant:hover .uc-ai-feedback-actions.svelte-1ramda1,\n  .uc-ai-feedback-actions.is-voted.svelte-1ramda1,\n  .uc-ai-feedback-actions.svelte-1ramda1:focus-within {opacity:1;}\n\n  /* Nothing hovers on a touch screen, and feedback nobody can see collects\n     nothing. */\n  @media (hover: none) {.uc-ai-feedback-actions.svelte-1ramda1 {opacity:1;}\n  }.uc-ai-feedback-btn.svelte-1ramda1 {display:inline-flex;align-items:center;border:none;\n    /* Same radius step and padding as the copy button beside it — the two used\n       to differ by an invisible amount that still made the row look uneven. */border-radius:var(--uc-chat-radius-sm);background:transparent;color:var(--uc-chat-component-text-muted-color);cursor:pointer;padding:0.15em 0.3em;font-size:1em;line-height:1;}.uc-ai-feedback-btn.svelte-1ramda1:hover:not(:disabled) {background-color:var(--uc-chat-hover-background-color);color:var(--uc-chat-component-text-title-color);}.uc-ai-feedback-btn.svelte-1ramda1:disabled {cursor:default;opacity:0.6;}\n\n  /* Same treatment an active reaction pill gets in channel mode, so \"selected\"\n     looks the same everywhere in the component. */.uc-ai-feedback-btn.is-active.svelte-1ramda1 {color:var(--uc-chat-accent-color);background-color:color-mix(\n      in srgb,\n      var(--uc-chat-accent-color) 12%,\n      transparent\n    );}.uc-ai-feedback-thanks.svelte-1ramda1 {color:var(--uc-chat-component-text-muted-color);}\n\n  /* Full-width so it wraps below the time/copy/thumbs line rather than squeezing\n     in beside them. */.uc-ai-feedback-panel.svelte-1ramda1 {flex:0 0 100%;display:flex;flex-direction:column;gap:var(--uc-chat-space-1);margin-top:var(--uc-chat-space-2);max-width:32em;\n    /* The meta row is 0.7em; scale back up so the box is readable on its own. */font-size:1.25em;}.uc-ai-feedback-label.svelte-1ramda1 {color:var(--uc-chat-component-text-muted-color);font-weight:400;}textarea.uc-ai-feedback-input.svelte-1ramda1 {width:100%;padding:0.4em 0.6em;resize:none;font-family:var(--uc-chat-font-base);font-size:1em;}.uc-ai-feedback-panel-footer.svelte-1ramda1 {display:flex;align-items:center;gap:var(--uc-chat-space-2);flex-wrap:wrap;}.uc-ai-feedback-hint.svelte-1ramda1 {flex:1;min-width:8em;color:var(--uc-chat-component-text-muted-color);font-size:0.85em;}"
	};
	function AiFeedbackControl($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css$20);
		/**
		* Conversation feedback: a quiet thumbs-up / thumbs-down pair, plus an optional
		* comment box on a thumbs-down.
		*
		* The glyphs are outlined (`fa-thumbs-o-*`) until a verdict is stored, and only
		* the chosen one fills in. An unanswered ask must not draw the eye, and the fill
		* is then what carries "this is your answer" rather than colour alone.
		*
		* Lives in the assistant message's action row next to the copy button, which is
		* where every mainstream AI chat puts it — passive and never blocking, so it
		* asks for nothing and interrupts nothing.
		*
		* Two deliberate behaviours:
		* - The **vote is submitted on click**, before the comment. An abandoned comment
		*   panel still leaves the rating behind, which is the signal that matters most.
		* - Clicking the active thumb **withdraws** the vote. A mis-click must not be
		*   permanent, and the stored comment goes with it (see set_session_feedback).
		*
		* The root is `display: contents` so the buttons become flex children of the
		* meta row while the panel wraps onto its own full-width line.
		*
		* @typedef {Object} Props
		* @property {aiFeedbackObject|null} [feedback] Verdict already given, or null when unrated
		* @property {(next: {rating: string|null, comment: string}) => Promise<void>} onSubmit
		*   Persists the verdict. Never rejects — the pane swallows and logs failures,
		*   because feedback failing must not interrupt a conversation.
		*/
		/** @type {Props} */
		let feedback = prop($$props, "feedback", 7, null), onSubmit = prop($$props, "onSubmit", 7);
		let rating = /* @__PURE__ */ user_derived(() => feedback()?.rating ?? null);
		let isUp = /* @__PURE__ */ user_derived(() => get(rating) === "up");
		let isDown = /* @__PURE__ */ user_derived(() => get(rating) === FEEDBACK_RATING_DOWN);
		let panelOpen = /* @__PURE__ */ state(false);
		let commentText = /* @__PURE__ */ state("");
		let saving = /* @__PURE__ */ state(false);
		let thanks = /* @__PURE__ */ state(false);
		let textarea = /* @__PURE__ */ state(void 0);
		let fieldId = `uc-ai-fb-${Math.random().toString(36).slice(2, 9)}`;
		let thanksTimer = null;
		function acknowledge() {
			set(thanks, true);
			clearTimeout(thanksTimer);
			thanksTimer = setTimeout(() => {
				set(thanks, false);
			}, 2500);
		}
		onDestroy(() => clearTimeout(thanksTimer));
		async function persist(nextRating, comment) {
			set(saving, true);
			try {
				await onSubmit()({
					rating: nextRating,
					comment
				});
			} finally {
				set(saving, false);
			}
		}
		async function vote(clicked) {
			let next = get(rating) === clicked ? null : clicked;
			if (next === "down") {
				set(commentText, "");
				set(panelOpen, true);
				await focusInput();
			} else {
				set(panelOpen, false);
				set(commentText, "");
			}
			await persist(next, next === "down" ? get(commentText) : "");
			if (next === "up") acknowledge();
		}
		async function focusInput() {
			await tick();
			get(textarea)?.focus();
		}
		async function sendComment() {
			set(panelOpen, false);
			await persist(FEEDBACK_RATING_DOWN, get(commentText));
			acknowledge();
		}
		function skipComment() {
			set(panelOpen, false);
			set(commentText, "");
			acknowledge();
		}
		function handleKeyDown(e) {
			if (e.key === "Escape") {
				e.stopPropagation();
				skipComment();
			}
		}
		var $$exports = {
			get feedback() {
				return feedback();
			},
			set feedback($$value = null) {
				feedback($$value);
				flushSync();
			},
			get onSubmit() {
				return onSubmit();
			},
			set onSubmit($$value) {
				onSubmit($$value);
				flushSync();
			}
		};
		var div = root$17();
		var span = child(div);
		let classes;
		var button = child(span);
		let classes_1;
		var span_1 = child(button);
		reset(button);
		var button_1 = sibling(button, 2);
		let classes_2;
		var span_2 = child(button_1);
		reset(button_1);
		var node = sibling(button_1, 2);
		var consequent = ($$anchor) => {
			var span_3 = root_1$15();
			var text = child(span_3, true);
			reset(span_3);
			template_effect(() => set_text(text, FEEDBACK_THANKS));
			append($$anchor, span_3);
		};
		if_block(node, ($$render) => {
			if (get(thanks)) $$render(consequent);
		});
		reset(span);
		var node_1 = sibling(span, 2);
		var consequent_1 = ($$anchor) => {
			var div_1 = root_2$19();
			var label = child(div_1);
			var text_1 = child(label, true);
			reset(label);
			var textarea_1 = sibling(label, 2);
			remove_textarea_child(textarea_1);
			bind_this(textarea_1, ($$value) => set(textarea, $$value), () => get(textarea));
			var div_2 = sibling(textarea_1, 2);
			var span_4 = child(div_2);
			var text_2 = child(span_4, true);
			reset(span_4);
			var button_2 = sibling(span_4, 2);
			var text_3 = child(button_2, true);
			reset(button_2);
			var button_3 = sibling(button_2, 2);
			var text_4 = child(button_3, true);
			reset(button_3);
			reset(div_2);
			reset(div_1);
			template_effect(() => {
				set_attribute(label, "for", fieldId);
				set_text(text_1, FEEDBACK_COMMENT_PROMPT);
				set_attribute(textarea_1, "id", fieldId);
				set_attribute(textarea_1, "maxlength", FEEDBACK_COMMENT_MAX);
				set_text(text_2, FEEDBACK_COMMENT_HINT);
				set_text(text_3, FEEDBACK_COMMENT_SKIP);
				button_3.disabled = get(saving);
				set_text(text_4, FEEDBACK_COMMENT_SEND);
			});
			delegated("keydown", div_1, handleKeyDown);
			bind_value(textarea_1, () => get(commentText), ($$value) => set(commentText, $$value));
			delegated("click", button_2, skipComment);
			delegated("click", button_3, sendComment);
			append($$anchor, div_1);
		};
		if_block(node_1, ($$render) => {
			if (get(panelOpen)) $$render(consequent_1);
		});
		reset(div);
		template_effect(() => {
			classes = set_class(span, 1, "uc-ai-feedback-actions svelte-1ramda1", null, classes, { "is-voted": get(rating) !== null });
			classes_1 = set_class(button, 1, "uc-ai-feedback-btn svelte-1ramda1", null, classes_1, { "is-active": get(isUp) });
			set_attribute(button, "aria-pressed", get(isUp));
			set_attribute(button, "aria-label", get(isUp) ? FEEDBACK_UP_LABEL_ACTIVE : FEEDBACK_UP_LABEL);
			set_attribute(button, "title", get(isUp) ? FEEDBACK_UP_LABEL_ACTIVE : FEEDBACK_UP_LABEL);
			button.disabled = get(saving);
			set_class(span_1, 1, `fa ${get(isUp) ? "fa-thumbs-up" : "fa-thumbs-o-up"}`);
			classes_2 = set_class(button_1, 1, "uc-ai-feedback-btn svelte-1ramda1", null, classes_2, { "is-active": get(isDown) });
			set_attribute(button_1, "aria-pressed", get(isDown));
			set_attribute(button_1, "aria-label", get(isDown) ? FEEDBACK_DOWN_LABEL_ACTIVE : FEEDBACK_DOWN_LABEL);
			set_attribute(button_1, "title", get(isDown) ? FEEDBACK_DOWN_LABEL_ACTIVE : FEEDBACK_DOWN_LABEL);
			button_1.disabled = get(saving);
			set_class(span_2, 1, `fa ${get(isDown) ? "fa-thumbs-down" : "fa-thumbs-o-down"}`);
		});
		delegated("click", button, () => vote("up"));
		delegated("click", button_1, () => vote(FEEDBACK_RATING_DOWN));
		append($$anchor, div);
		return pop($$exports);
	}
	delegate(["click", "keydown"]);
	create_custom_element(AiFeedbackControl, {
		feedback: {},
		onSubmit: {}
	}, [], [], { mode: "open" });
	//#endregion
	//#region node_modules/dompurify/dist/purify.es.mjs
	/*! @license DOMPurify 3.4.12 | (c) Cure53 and other contributors | Released under the Apache license 2.0 and Mozilla Public License 2.0 | github.com/cure53/DOMPurify/blob/3.4.12/LICENSE */
	function _arrayLikeToArray(r, a) {
		(null == a || a > r.length) && (a = r.length);
		for (var e = 0, n = Array(a); e < a; e++) n[e] = r[e];
		return n;
	}
	function _arrayWithHoles(r) {
		if (Array.isArray(r)) return r;
	}
	function _iterableToArrayLimit(r, l) {
		var t = null == r ? null : "undefined" != typeof Symbol && r[Symbol.iterator] || r["@@iterator"];
		if (null != t) {
			var e, n, i, u, a = [], f = true, o = false;
			try {
				if (i = (t = t.call(r)).next, 0 === l);
				else for (; !(f = (e = i.call(t)).done) && (a.push(e.value), a.length !== l); f = !0);
			} catch (r) {
				o = true, n = r;
			} finally {
				try {
					if (!f && null != t.return && (u = t.return(), Object(u) !== u)) return;
				} finally {
					if (o) throw n;
				}
			}
			return a;
		}
	}
	function _nonIterableRest() {
		throw new TypeError("Invalid attempt to destructure non-iterable instance.\nIn order to be iterable, non-array objects must have a [Symbol.iterator]() method.");
	}
	function _slicedToArray(r, e) {
		return _arrayWithHoles(r) || _iterableToArrayLimit(r, e) || _unsupportedIterableToArray(r, e) || _nonIterableRest();
	}
	function _unsupportedIterableToArray(r, a) {
		if (r) {
			if ("string" == typeof r) return _arrayLikeToArray(r, a);
			var t = {}.toString.call(r).slice(8, -1);
			return "Object" === t && r.constructor && (t = r.constructor.name), "Map" === t || "Set" === t ? Array.from(r) : "Arguments" === t || /^(?:Ui|I)nt(?:8|16|32)(?:Clamped)?Array$/.test(t) ? _arrayLikeToArray(r, a) : void 0;
		}
	}
	var entries = Object.entries, setPrototypeOf = Object.setPrototypeOf, isFrozen = Object.isFrozen, getPrototypeOf = Object.getPrototypeOf, getOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;
	var freeze = Object.freeze, seal = Object.seal, create = Object.create;
	var _ref = typeof Reflect !== "undefined" && Reflect, apply = _ref.apply, construct = _ref.construct;
	if (!freeze) freeze = function freeze(x) {
		return x;
	};
	if (!seal) seal = function seal(x) {
		return x;
	};
	if (!apply) apply = function apply(func, thisArg) {
		for (var _len = arguments.length, args = new Array(_len > 2 ? _len - 2 : 0), _key = 2; _key < _len; _key++) args[_key - 2] = arguments[_key];
		return func.apply(thisArg, args);
	};
	if (!construct) construct = function construct(Func) {
		for (var _len2 = arguments.length, args = new Array(_len2 > 1 ? _len2 - 1 : 0), _key2 = 1; _key2 < _len2; _key2++) args[_key2 - 1] = arguments[_key2];
		return new Func(...args);
	};
	var arrayForEach = unapply(Array.prototype.forEach);
	var arrayLastIndexOf = unapply(Array.prototype.lastIndexOf);
	var arrayPop = unapply(Array.prototype.pop);
	var arrayPush = unapply(Array.prototype.push);
	var arraySplice = unapply(Array.prototype.splice);
	var arrayIsArray = Array.isArray;
	var stringToLowerCase = unapply(String.prototype.toLowerCase);
	var stringToString = unapply(String.prototype.toString);
	var stringMatch = unapply(String.prototype.match);
	var stringReplace = unapply(String.prototype.replace);
	var stringIndexOf = unapply(String.prototype.indexOf);
	var stringTrim = unapply(String.prototype.trim);
	var numberToString = unapply(Number.prototype.toString);
	var booleanToString = unapply(Boolean.prototype.toString);
	var bigintToString = typeof BigInt === "undefined" ? null : unapply(BigInt.prototype.toString);
	var symbolToString = typeof Symbol === "undefined" ? null : unapply(Symbol.prototype.toString);
	var objectHasOwnProperty = unapply(Object.prototype.hasOwnProperty);
	var objectToString = unapply(Object.prototype.toString);
	var regExpTest = unapply(RegExp.prototype.test);
	var typeErrorCreate = unconstruct(TypeError);
	/**
	* Creates a new function that calls the given function with a specified thisArg and arguments.
	*
	* @param func - The function to be wrapped and called.
	* @returns A new function that calls the given function with a specified thisArg and arguments.
	*/
	function unapply(func) {
		return function(thisArg) {
			if (thisArg instanceof RegExp) thisArg.lastIndex = 0;
			for (var _len3 = arguments.length, args = new Array(_len3 > 1 ? _len3 - 1 : 0), _key3 = 1; _key3 < _len3; _key3++) args[_key3 - 1] = arguments[_key3];
			return apply(func, thisArg, args);
		};
	}
	/**
	* Creates a new function that constructs an instance of the given constructor function with the provided arguments.
	*
	* @param func - The constructor function to be wrapped and called.
	* @returns A new function that constructs an instance of the given constructor function with the provided arguments.
	*/
	function unconstruct(Func) {
		return function() {
			for (var _len4 = arguments.length, args = new Array(_len4), _key4 = 0; _key4 < _len4; _key4++) args[_key4] = arguments[_key4];
			return construct(Func, args);
		};
	}
	/**
	* Add properties to a lookup table
	*
	* @param set - The set to which elements will be added.
	* @param array - The array containing elements to be added to the set.
	* @param transformCaseFunc - An optional function to transform the case of each element before adding to the set.
	* @returns The modified set with added elements.
	*/
	function addToSet(set, array) {
		let transformCaseFunc = arguments.length > 2 && arguments[2] !== void 0 ? arguments[2] : stringToLowerCase;
		if (setPrototypeOf) setPrototypeOf(set, null);
		if (!arrayIsArray(array)) return set;
		let l = array.length;
		while (l--) {
			let element = array[l];
			if (typeof element === "string") {
				const lcElement = transformCaseFunc(element);
				if (lcElement !== element) {
					if (!isFrozen(array)) array[l] = lcElement;
					element = lcElement;
				}
			}
			set[element] = true;
		}
		return set;
	}
	/**
	* Clean up an array to harden against CSPP
	*
	* @param array - The array to be cleaned.
	* @returns The cleaned version of the array
	*/
	function cleanArray(array) {
		for (let index = 0; index < array.length; index++) if (!objectHasOwnProperty(array, index)) array[index] = null;
		return array;
	}
	/**
	* Shallow clone an object
	*
	* @param object - The object to be cloned.
	* @returns A new object that copies the original.
	*/
	function clone(object) {
		const newObject = create(null);
		for (const _ref2 of entries(object)) {
			var _ref3 = _slicedToArray(_ref2, 2);
			const property = _ref3[0];
			const value = _ref3[1];
			if (objectHasOwnProperty(object, property)) if (arrayIsArray(value)) newObject[property] = cleanArray(value);
			else if (value && typeof value === "object" && value.constructor === Object) newObject[property] = clone(value);
			else newObject[property] = value;
		}
		return newObject;
	}
	/**
	* Convert non-node values into strings without depending on direct property access.
	*
	* @param value - The value to stringify.
	* @returns A string representation of the provided value.
	*/
	function stringifyValue(value) {
		switch (typeof value) {
			case "string": return value;
			case "number": return numberToString(value);
			case "boolean": return booleanToString(value);
			case "bigint": return bigintToString ? bigintToString(value) : "0";
			case "symbol": return symbolToString ? symbolToString(value) : "Symbol()";
			case "undefined": return objectToString(value);
			case "function":
			case "object": {
				if (value === null) return objectToString(value);
				const valueAsRecord = value;
				const valueToString = lookupGetter(valueAsRecord, "toString");
				if (typeof valueToString === "function") {
					const stringified = valueToString(valueAsRecord);
					return typeof stringified === "string" ? stringified : objectToString(stringified);
				}
				return objectToString(value);
			}
			default: return objectToString(value);
		}
	}
	/**
	* This method automatically checks if the prop is function or getter and behaves accordingly.
	*
	* @param object - The object to look up the getter function in its prototype chain.
	* @param prop - The property name for which to find the getter function.
	* @returns The getter function found in the prototype chain or a fallback function.
	*/
	function lookupGetter(object, prop) {
		while (object !== null) {
			const desc = getOwnPropertyDescriptor(object, prop);
			if (desc) {
				if (desc.get) return unapply(desc.get);
				if (typeof desc.value === "function") return unapply(desc.value);
			}
			object = getPrototypeOf(object);
		}
		function fallbackValue() {
			return null;
		}
		return fallbackValue;
	}
	function isRegex(value) {
		try {
			regExpTest(value, "");
			return true;
		} catch (_unused) {
			return false;
		}
	}
	var html$1 = freeze([
		"a",
		"abbr",
		"acronym",
		"address",
		"area",
		"article",
		"aside",
		"audio",
		"b",
		"bdi",
		"bdo",
		"big",
		"blink",
		"blockquote",
		"body",
		"br",
		"button",
		"canvas",
		"caption",
		"center",
		"cite",
		"code",
		"col",
		"colgroup",
		"content",
		"data",
		"datalist",
		"dd",
		"decorator",
		"del",
		"details",
		"dfn",
		"dialog",
		"dir",
		"div",
		"dl",
		"dt",
		"element",
		"em",
		"fieldset",
		"figcaption",
		"figure",
		"font",
		"footer",
		"form",
		"h1",
		"h2",
		"h3",
		"h4",
		"h5",
		"h6",
		"head",
		"header",
		"hgroup",
		"hr",
		"html",
		"i",
		"img",
		"input",
		"ins",
		"kbd",
		"label",
		"legend",
		"li",
		"main",
		"map",
		"mark",
		"marquee",
		"menu",
		"menuitem",
		"meter",
		"nav",
		"nobr",
		"ol",
		"optgroup",
		"option",
		"output",
		"p",
		"picture",
		"pre",
		"progress",
		"q",
		"rp",
		"rt",
		"ruby",
		"s",
		"samp",
		"search",
		"section",
		"select",
		"shadow",
		"slot",
		"small",
		"source",
		"spacer",
		"span",
		"strike",
		"strong",
		"style",
		"sub",
		"summary",
		"sup",
		"table",
		"tbody",
		"td",
		"template",
		"textarea",
		"tfoot",
		"th",
		"thead",
		"time",
		"tr",
		"track",
		"tt",
		"u",
		"ul",
		"var",
		"video",
		"wbr"
	]);
	var svg$1 = freeze([
		"svg",
		"a",
		"altglyph",
		"altglyphdef",
		"altglyphitem",
		"animatecolor",
		"animatemotion",
		"animatetransform",
		"circle",
		"clippath",
		"defs",
		"desc",
		"ellipse",
		"enterkeyhint",
		"exportparts",
		"filter",
		"font",
		"g",
		"glyph",
		"glyphref",
		"hkern",
		"image",
		"inputmode",
		"line",
		"lineargradient",
		"marker",
		"mask",
		"metadata",
		"mpath",
		"part",
		"path",
		"pattern",
		"polygon",
		"polyline",
		"radialgradient",
		"rect",
		"stop",
		"style",
		"switch",
		"symbol",
		"text",
		"textpath",
		"title",
		"tref",
		"tspan",
		"view",
		"vkern"
	]);
	var svgFilters = freeze([
		"feBlend",
		"feColorMatrix",
		"feComponentTransfer",
		"feComposite",
		"feConvolveMatrix",
		"feDiffuseLighting",
		"feDisplacementMap",
		"feDistantLight",
		"feDropShadow",
		"feFlood",
		"feFuncA",
		"feFuncB",
		"feFuncG",
		"feFuncR",
		"feGaussianBlur",
		"feImage",
		"feMerge",
		"feMergeNode",
		"feMorphology",
		"feOffset",
		"fePointLight",
		"feSpecularLighting",
		"feSpotLight",
		"feTile",
		"feTurbulence"
	]);
	var svgDisallowed = freeze([
		"animate",
		"color-profile",
		"cursor",
		"discard",
		"font-face",
		"font-face-format",
		"font-face-name",
		"font-face-src",
		"font-face-uri",
		"foreignobject",
		"hatch",
		"hatchpath",
		"mesh",
		"meshgradient",
		"meshpatch",
		"meshrow",
		"missing-glyph",
		"script",
		"set",
		"solidcolor",
		"unknown",
		"use"
	]);
	var mathMl$1 = freeze([
		"math",
		"menclose",
		"merror",
		"mfenced",
		"mfrac",
		"mglyph",
		"mi",
		"mlabeledtr",
		"mmultiscripts",
		"mn",
		"mo",
		"mover",
		"mpadded",
		"mphantom",
		"mroot",
		"mrow",
		"ms",
		"mspace",
		"msqrt",
		"mstyle",
		"msub",
		"msup",
		"msubsup",
		"mtable",
		"mtd",
		"mtext",
		"mtr",
		"munder",
		"munderover",
		"mprescripts"
	]);
	var mathMlDisallowed = freeze([
		"maction",
		"maligngroup",
		"malignmark",
		"mlongdiv",
		"mscarries",
		"mscarry",
		"msgroup",
		"mstack",
		"msline",
		"msrow",
		"semantics",
		"annotation",
		"annotation-xml",
		"mprescripts",
		"none"
	]);
	var text = freeze(["#text"]);
	var html = freeze([
		"accept",
		"action",
		"align",
		"alt",
		"autocapitalize",
		"autocomplete",
		"autopictureinpicture",
		"autoplay",
		"background",
		"bgcolor",
		"border",
		"capture",
		"cellpadding",
		"cellspacing",
		"checked",
		"cite",
		"class",
		"clear",
		"color",
		"cols",
		"colspan",
		"command",
		"commandfor",
		"controls",
		"controlslist",
		"coords",
		"crossorigin",
		"datetime",
		"decoding",
		"default",
		"dir",
		"disabled",
		"disablepictureinpicture",
		"disableremoteplayback",
		"download",
		"draggable",
		"enctype",
		"enterkeyhint",
		"exportparts",
		"face",
		"for",
		"headers",
		"height",
		"hidden",
		"high",
		"href",
		"hreflang",
		"id",
		"inert",
		"inputmode",
		"integrity",
		"ismap",
		"kind",
		"label",
		"lang",
		"list",
		"loading",
		"loop",
		"low",
		"max",
		"maxlength",
		"media",
		"method",
		"min",
		"minlength",
		"multiple",
		"muted",
		"name",
		"nonce",
		"noshade",
		"novalidate",
		"nowrap",
		"open",
		"optimum",
		"part",
		"pattern",
		"placeholder",
		"playsinline",
		"popover",
		"popovertarget",
		"popovertargetaction",
		"poster",
		"preload",
		"pubdate",
		"radiogroup",
		"readonly",
		"rel",
		"required",
		"rev",
		"reversed",
		"role",
		"rows",
		"rowspan",
		"spellcheck",
		"scope",
		"selected",
		"shape",
		"size",
		"sizes",
		"slot",
		"span",
		"srclang",
		"start",
		"src",
		"srcset",
		"step",
		"style",
		"summary",
		"tabindex",
		"title",
		"translate",
		"type",
		"usemap",
		"valign",
		"value",
		"width",
		"wrap",
		"xmlns"
	]);
	var svg = freeze([
		"accent-height",
		"accumulate",
		"additive",
		"alignment-baseline",
		"amplitude",
		"ascent",
		"attributename",
		"attributetype",
		"azimuth",
		"basefrequency",
		"baseline-shift",
		"begin",
		"bias",
		"by",
		"class",
		"clip",
		"clippathunits",
		"clip-path",
		"clip-rule",
		"color",
		"color-interpolation",
		"color-interpolation-filters",
		"color-profile",
		"color-rendering",
		"cx",
		"cy",
		"d",
		"dx",
		"dy",
		"diffuseconstant",
		"direction",
		"display",
		"divisor",
		"dominant-baseline",
		"dur",
		"edgemode",
		"elevation",
		"end",
		"exponent",
		"fill",
		"fill-opacity",
		"fill-rule",
		"filter",
		"filterunits",
		"flood-color",
		"flood-opacity",
		"font-family",
		"font-size",
		"font-size-adjust",
		"font-stretch",
		"font-style",
		"font-variant",
		"font-weight",
		"fx",
		"fy",
		"g1",
		"g2",
		"glyph-name",
		"glyphref",
		"gradientunits",
		"gradienttransform",
		"height",
		"href",
		"id",
		"image-rendering",
		"in",
		"in2",
		"intercept",
		"k",
		"k1",
		"k2",
		"k3",
		"k4",
		"kerning",
		"keypoints",
		"keysplines",
		"keytimes",
		"lang",
		"lengthadjust",
		"letter-spacing",
		"kernelmatrix",
		"kernelunitlength",
		"lighting-color",
		"local",
		"marker-end",
		"marker-mid",
		"marker-start",
		"markerheight",
		"markerunits",
		"markerwidth",
		"maskcontentunits",
		"maskunits",
		"max",
		"mask",
		"mask-type",
		"media",
		"method",
		"mode",
		"min",
		"name",
		"numoctaves",
		"offset",
		"operator",
		"opacity",
		"order",
		"orient",
		"orientation",
		"origin",
		"overflow",
		"paint-order",
		"path",
		"pathlength",
		"patterncontentunits",
		"patterntransform",
		"patternunits",
		"points",
		"preservealpha",
		"preserveaspectratio",
		"primitiveunits",
		"r",
		"rx",
		"ry",
		"radius",
		"refx",
		"refy",
		"repeatcount",
		"repeatdur",
		"restart",
		"result",
		"rotate",
		"scale",
		"seed",
		"shape-rendering",
		"slope",
		"specularconstant",
		"specularexponent",
		"spreadmethod",
		"startoffset",
		"stddeviation",
		"stitchtiles",
		"stop-color",
		"stop-opacity",
		"stroke-dasharray",
		"stroke-dashoffset",
		"stroke-linecap",
		"stroke-linejoin",
		"stroke-miterlimit",
		"stroke-opacity",
		"stroke",
		"stroke-width",
		"style",
		"surfacescale",
		"systemlanguage",
		"tabindex",
		"tablevalues",
		"targetx",
		"targety",
		"transform",
		"transform-origin",
		"text-anchor",
		"text-decoration",
		"text-orientation",
		"text-rendering",
		"textlength",
		"type",
		"u1",
		"u2",
		"unicode",
		"values",
		"viewbox",
		"visibility",
		"version",
		"vert-adv-y",
		"vert-origin-x",
		"vert-origin-y",
		"width",
		"word-spacing",
		"wrap",
		"writing-mode",
		"xchannelselector",
		"ychannelselector",
		"x",
		"x1",
		"x2",
		"xmlns",
		"y",
		"y1",
		"y2",
		"z",
		"zoomandpan"
	]);
	var mathMl = freeze([
		"accent",
		"accentunder",
		"align",
		"bevelled",
		"close",
		"columnalign",
		"columnlines",
		"columnspacing",
		"columnspan",
		"denomalign",
		"depth",
		"dir",
		"display",
		"displaystyle",
		"encoding",
		"fence",
		"frame",
		"height",
		"href",
		"id",
		"largeop",
		"length",
		"linethickness",
		"lquote",
		"lspace",
		"mathbackground",
		"mathcolor",
		"mathsize",
		"mathvariant",
		"maxsize",
		"minsize",
		"movablelimits",
		"notation",
		"numalign",
		"open",
		"rowalign",
		"rowlines",
		"rowspacing",
		"rowspan",
		"rspace",
		"rquote",
		"scriptlevel",
		"scriptminsize",
		"scriptsizemultiplier",
		"selection",
		"separator",
		"separators",
		"stretchy",
		"subscriptshift",
		"supscriptshift",
		"symmetric",
		"voffset",
		"width",
		"xmlns"
	]);
	var xml = freeze([
		"xlink:href",
		"xml:id",
		"xlink:title",
		"xml:space",
		"xmlns:xlink"
	]);
	var MUSTACHE_EXPR = seal(/{{[\w\W]*|^[\w\W]*}}/g);
	var ERB_EXPR = seal(/<%[\w\W]*|^[\w\W]*%>/g);
	var TMPLIT_EXPR = seal(/\${[\w\W]*/g);
	var DATA_ATTR = seal(/^data-[\-\w.\u00B7-\uFFFF]+$/);
	var ARIA_ATTR = seal(/^aria-[\-\w]+$/);
	var IS_ALLOWED_URI = seal(/^(?:(?:(?:f|ht)tps?|mailto|tel|callto|sms|cid|xmpp|matrix):|[^a-z]|[a-z+.\-]+(?:[^a-z+.\-:]|$))/i);
	var IS_SCRIPT_OR_DATA = seal(/^(?:\w+script|data):/i);
	var ATTR_WHITESPACE = seal(/[\u0000-\u0020\u00A0\u1680\u180E\u2000-\u2029\u205F\u3000]/g);
	var DOCTYPE_NAME = seal(/^html$/i);
	var CUSTOM_ELEMENT = seal(/^[a-z][.\w]*(-[.\w]+)+$/i);
	var ELEMENT_MARKUP_PROBE = seal(/<[/\w!]/g);
	var COMMENT_MARKUP_PROBE = seal(/<[/\w]/g);
	var FALLBACK_TAG_CLOSE = seal(/<\/no(script|embed|frames)/i);
	var SELF_CLOSING_TAG = seal(/\/>/i);
	var NODE_TYPE = {
		element: 1,
		attribute: 2,
		text: 3,
		cdataSection: 4,
		entityReference: 5,
		entityNode: 6,
		processingInstruction: 7,
		comment: 8,
		document: 9,
		documentType: 10,
		documentFragment: 11,
		notation: 12
	};
	var getGlobal = function getGlobal() {
		return typeof window === "undefined" ? null : window;
	};
	/**
	* Creates a no-op policy for internal use only.
	* Don't export this function outside this module!
	* @param trustedTypes The policy factory.
	* @param purifyHostElement The Script element used to load DOMPurify (to determine policy name suffix).
	* @return The policy created (or null, if Trusted Types
	* are not supported or creating the policy failed).
	*/
	var _createTrustedTypesPolicy = function _createTrustedTypesPolicy(trustedTypes, purifyHostElement) {
		if (typeof trustedTypes !== "object" || typeof trustedTypes.createPolicy !== "function") return null;
		let suffix = null;
		const ATTR_NAME = "data-tt-policy-suffix";
		if (purifyHostElement && purifyHostElement.hasAttribute(ATTR_NAME)) suffix = purifyHostElement.getAttribute(ATTR_NAME);
		const policyName = "dompurify" + (suffix ? "#" + suffix : "");
		try {
			return trustedTypes.createPolicy(policyName, {
				createHTML(html) {
					return html;
				},
				createScriptURL(scriptUrl) {
					return scriptUrl;
				}
			});
		} catch (_) {
			console.warn("TrustedTypes policy " + policyName + " could not be created.");
			return null;
		}
	};
	var _createHooksMap = function _createHooksMap() {
		return {
			afterSanitizeAttributes: [],
			afterSanitizeElements: [],
			afterSanitizeShadowDOM: [],
			beforeSanitizeAttributes: [],
			beforeSanitizeElements: [],
			beforeSanitizeShadowDOM: [],
			uponSanitizeAttribute: [],
			uponSanitizeElement: [],
			uponSanitizeShadowNode: []
		};
	};
	/**
	* Resolve a set-valued configuration option: a fresh set built from
	* cfg[key] when it is an own array property (seeded with a clone of
	* options.base when given, case-normalized via options.transform),
	* the fallback set otherwise.
	*
	* @param cfg the cloned, prototype-free configuration object
	* @param key the configuration property to read
	* @param fallback the set to use when the option is absent or not an array
	* @param options transform and optional base set to merge into
	* @returns the resolved set
	*/
	var _resolveSetOption = function _resolveSetOption(cfg, key, fallback, options) {
		return objectHasOwnProperty(cfg, key) && arrayIsArray(cfg[key]) ? addToSet(options.base ? clone(options.base) : {}, cfg[key], options.transform) : fallback;
	};
	function createDOMPurify() {
		let window = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : getGlobal();
		const DOMPurify = (root) => createDOMPurify(root);
		DOMPurify.version = "3.4.12";
		DOMPurify.removed = [];
		if (!window || !window.document || window.document.nodeType !== NODE_TYPE.document || !window.Element) {
			DOMPurify.isSupported = false;
			return DOMPurify;
		}
		let document = window.document;
		const originalDocument = document;
		const currentScript = originalDocument.currentScript;
		window.DocumentFragment;
		const HTMLTemplateElement = window.HTMLTemplateElement, Node = window.Node, Element = window.Element, NodeFilter = window.NodeFilter;
		window.NamedNodeMap === void 0 && (window.NamedNodeMap || window.MozNamedAttrMap);
		window.HTMLFormElement;
		const DOMParser = window.DOMParser, trustedTypes = window.trustedTypes;
		const ElementPrototype = Element.prototype;
		const cloneNode = lookupGetter(ElementPrototype, "cloneNode");
		const remove = lookupGetter(ElementPrototype, "remove");
		const getNextSibling = lookupGetter(ElementPrototype, "nextSibling");
		const getChildNodes = lookupGetter(ElementPrototype, "childNodes");
		const getParentNode = lookupGetter(ElementPrototype, "parentNode");
		const getShadowRoot = lookupGetter(ElementPrototype, "shadowRoot");
		const getAttributes = lookupGetter(ElementPrototype, "attributes");
		const getNodeType = Node && Node.prototype ? lookupGetter(Node.prototype, "nodeType") : null;
		const getNodeName = Node && Node.prototype ? lookupGetter(Node.prototype, "nodeName") : null;
		if (typeof HTMLTemplateElement === "function") {
			const template = document.createElement("template");
			if (template.content && template.content.ownerDocument) document = template.content.ownerDocument;
		}
		let trustedTypesPolicy;
		let emptyHTML = "";
		let defaultTrustedTypesPolicy;
		let defaultTrustedTypesPolicyResolved = false;
		let IN_TRUSTED_TYPES_POLICY = 0;
		const _assertNotInTrustedTypesPolicy = function _assertNotInTrustedTypesPolicy() {
			if (IN_TRUSTED_TYPES_POLICY > 0) throw typeErrorCreate("A configured TRUSTED_TYPES_POLICY callback (createHTML or createScriptURL) must not call DOMPurify.sanitize, as that causes infinite recursion. Do not pass a policy whose callbacks wrap DOMPurify as TRUSTED_TYPES_POLICY; see the \"DOMPurify and Trusted Types\" section of the README.");
		};
		const _createTrustedHTML = function _createTrustedHTML(html) {
			_assertNotInTrustedTypesPolicy();
			IN_TRUSTED_TYPES_POLICY++;
			try {
				return trustedTypesPolicy.createHTML(html);
			} finally {
				IN_TRUSTED_TYPES_POLICY--;
			}
		};
		const _createTrustedScriptURL = function _createTrustedScriptURL(scriptUrl) {
			_assertNotInTrustedTypesPolicy();
			IN_TRUSTED_TYPES_POLICY++;
			try {
				return trustedTypesPolicy.createScriptURL(scriptUrl);
			} finally {
				IN_TRUSTED_TYPES_POLICY--;
			}
		};
		const _getDefaultTrustedTypesPolicy = function _getDefaultTrustedTypesPolicy() {
			if (!defaultTrustedTypesPolicyResolved) {
				defaultTrustedTypesPolicy = _createTrustedTypesPolicy(trustedTypes, currentScript);
				defaultTrustedTypesPolicyResolved = true;
			}
			return defaultTrustedTypesPolicy;
		};
		const _document = document, implementation = _document.implementation, createNodeIterator = _document.createNodeIterator, createDocumentFragment = _document.createDocumentFragment, getElementsByTagName = _document.getElementsByTagName;
		const importNode = originalDocument.importNode;
		let hooks = _createHooksMap();
		/**
		* Expose whether this browser supports running the full DOMPurify.
		*/
		DOMPurify.isSupported = typeof entries === "function" && typeof getParentNode === "function" && implementation && implementation.createHTMLDocument !== void 0;
		const MUSTACHE_EXPR$1 = MUSTACHE_EXPR, ERB_EXPR$1 = ERB_EXPR, TMPLIT_EXPR$1 = TMPLIT_EXPR, DATA_ATTR$1 = DATA_ATTR, ARIA_ATTR$1 = ARIA_ATTR, IS_SCRIPT_OR_DATA$1 = IS_SCRIPT_OR_DATA, ATTR_WHITESPACE$1 = ATTR_WHITESPACE, CUSTOM_ELEMENT$1 = CUSTOM_ELEMENT;
		let IS_ALLOWED_URI$1 = IS_ALLOWED_URI;
		/**
		* We consider the elements and attributes below to be safe. Ideally
		* don't add any new ones but feel free to remove unwanted ones.
		*/
		let ALLOWED_TAGS = null;
		const DEFAULT_ALLOWED_TAGS = addToSet({}, [
			...html$1,
			...svg$1,
			...svgFilters,
			...mathMl$1,
			...text
		]);
		let ALLOWED_ATTR = null;
		const DEFAULT_ALLOWED_ATTR = addToSet({}, [
			...html,
			...svg,
			...mathMl,
			...xml
		]);
		let CUSTOM_ELEMENT_HANDLING = Object.seal(create(null, {
			tagNameCheck: {
				writable: true,
				configurable: false,
				enumerable: true,
				value: null
			},
			attributeNameCheck: {
				writable: true,
				configurable: false,
				enumerable: true,
				value: null
			},
			allowCustomizedBuiltInElements: {
				writable: true,
				configurable: false,
				enumerable: true,
				value: false
			}
		}));
		let FORBID_TAGS = null;
		let FORBID_ATTR = null;
		const EXTRA_ELEMENT_HANDLING = Object.seal(create(null, {
			tagCheck: {
				writable: true,
				configurable: false,
				enumerable: true,
				value: null
			},
			attributeCheck: {
				writable: true,
				configurable: false,
				enumerable: true,
				value: null
			}
		}));
		let ALLOW_ARIA_ATTR = true;
		let ALLOW_DATA_ATTR = true;
		let ALLOW_UNKNOWN_PROTOCOLS = false;
		let ALLOW_SELF_CLOSE_IN_ATTR = true;
		let SAFE_FOR_TEMPLATES = false;
		let SAFE_FOR_XML = true;
		let WHOLE_DOCUMENT = false;
		let SET_CONFIG = false;
		let SET_CONFIG_ALLOWED_TAGS = null;
		let SET_CONFIG_ALLOWED_ATTR = null;
		let FORCE_BODY = false;
		let RETURN_DOM = false;
		let RETURN_DOM_FRAGMENT = false;
		let RETURN_TRUSTED_TYPE = false;
		let SANITIZE_DOM = true;
		let SANITIZE_NAMED_PROPS = false;
		const SANITIZE_NAMED_PROPS_PREFIX = "user-content-";
		let KEEP_CONTENT = true;
		let IN_PLACE = false;
		let USE_PROFILES = {};
		let FORBID_CONTENTS = null;
		const DEFAULT_FORBID_CONTENTS = addToSet({}, [
			"annotation-xml",
			"audio",
			"colgroup",
			"desc",
			"foreignobject",
			"head",
			"iframe",
			"math",
			"mi",
			"mn",
			"mo",
			"ms",
			"mtext",
			"noembed",
			"noframes",
			"noscript",
			"plaintext",
			"script",
			"selectedcontent",
			"style",
			"svg",
			"template",
			"thead",
			"title",
			"video",
			"xmp"
		]);
		let DATA_URI_TAGS = null;
		const DEFAULT_DATA_URI_TAGS = addToSet({}, [
			"audio",
			"video",
			"img",
			"source",
			"image",
			"track"
		]);
		let URI_SAFE_ATTRIBUTES = null;
		const DEFAULT_URI_SAFE_ATTRIBUTES = addToSet({}, [
			"alt",
			"class",
			"for",
			"id",
			"label",
			"name",
			"pattern",
			"placeholder",
			"role",
			"summary",
			"title",
			"value",
			"style",
			"xmlns"
		]);
		const MATHML_NAMESPACE = "http://www.w3.org/1998/Math/MathML";
		const SVG_NAMESPACE = "http://www.w3.org/2000/svg";
		const HTML_NAMESPACE = "http://www.w3.org/1999/xhtml";
		let NAMESPACE = HTML_NAMESPACE;
		let IS_EMPTY_INPUT = false;
		let ALLOWED_NAMESPACES = null;
		const DEFAULT_ALLOWED_NAMESPACES = addToSet({}, [
			MATHML_NAMESPACE,
			SVG_NAMESPACE,
			HTML_NAMESPACE
		], stringToString);
		const DEFAULT_MATHML_TEXT_INTEGRATION_POINTS = freeze([
			"mi",
			"mo",
			"mn",
			"ms",
			"mtext"
		]);
		let MATHML_TEXT_INTEGRATION_POINTS = addToSet({}, DEFAULT_MATHML_TEXT_INTEGRATION_POINTS);
		const DEFAULT_HTML_INTEGRATION_POINTS = freeze(["annotation-xml"]);
		let HTML_INTEGRATION_POINTS = addToSet({}, DEFAULT_HTML_INTEGRATION_POINTS);
		const COMMON_SVG_AND_HTML_ELEMENTS = addToSet({}, [
			"title",
			"style",
			"font",
			"a",
			"script"
		]);
		let PARSER_MEDIA_TYPE = null;
		const SUPPORTED_PARSER_MEDIA_TYPES = ["application/xhtml+xml", "text/html"];
		const DEFAULT_PARSER_MEDIA_TYPE = "text/html";
		let transformCaseFunc = null;
		let CONFIG = null;
		const formElement = document.createElement("form");
		const isRegexOrFunction = function isRegexOrFunction(testValue) {
			return testValue instanceof RegExp || testValue instanceof Function;
		};
		/**
		* _parseConfig
		*
		* @param cfg optional config literal
		*/
		const _parseConfig = function _parseConfig() {
			let cfg = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : {};
			if (CONFIG && CONFIG === cfg) return;
			if (!cfg || typeof cfg !== "object") cfg = {};
			cfg = clone(cfg);
			PARSER_MEDIA_TYPE = SUPPORTED_PARSER_MEDIA_TYPES.indexOf(cfg.PARSER_MEDIA_TYPE) === -1 ? DEFAULT_PARSER_MEDIA_TYPE : cfg.PARSER_MEDIA_TYPE;
			transformCaseFunc = PARSER_MEDIA_TYPE === "application/xhtml+xml" ? stringToString : stringToLowerCase;
			ALLOWED_TAGS = _resolveSetOption(cfg, "ALLOWED_TAGS", DEFAULT_ALLOWED_TAGS, { transform: transformCaseFunc });
			ALLOWED_ATTR = _resolveSetOption(cfg, "ALLOWED_ATTR", DEFAULT_ALLOWED_ATTR, { transform: transformCaseFunc });
			ALLOWED_NAMESPACES = _resolveSetOption(cfg, "ALLOWED_NAMESPACES", DEFAULT_ALLOWED_NAMESPACES, { transform: stringToString });
			URI_SAFE_ATTRIBUTES = _resolveSetOption(cfg, "ADD_URI_SAFE_ATTR", DEFAULT_URI_SAFE_ATTRIBUTES, {
				transform: transformCaseFunc,
				base: DEFAULT_URI_SAFE_ATTRIBUTES
			});
			DATA_URI_TAGS = _resolveSetOption(cfg, "ADD_DATA_URI_TAGS", DEFAULT_DATA_URI_TAGS, {
				transform: transformCaseFunc,
				base: DEFAULT_DATA_URI_TAGS
			});
			FORBID_CONTENTS = _resolveSetOption(cfg, "FORBID_CONTENTS", DEFAULT_FORBID_CONTENTS, { transform: transformCaseFunc });
			FORBID_TAGS = _resolveSetOption(cfg, "FORBID_TAGS", clone({}), { transform: transformCaseFunc });
			FORBID_ATTR = _resolveSetOption(cfg, "FORBID_ATTR", clone({}), { transform: transformCaseFunc });
			USE_PROFILES = objectHasOwnProperty(cfg, "USE_PROFILES") ? cfg.USE_PROFILES && typeof cfg.USE_PROFILES === "object" ? clone(cfg.USE_PROFILES) : cfg.USE_PROFILES : false;
			ALLOW_ARIA_ATTR = cfg.ALLOW_ARIA_ATTR !== false;
			ALLOW_DATA_ATTR = cfg.ALLOW_DATA_ATTR !== false;
			ALLOW_UNKNOWN_PROTOCOLS = cfg.ALLOW_UNKNOWN_PROTOCOLS || false;
			ALLOW_SELF_CLOSE_IN_ATTR = cfg.ALLOW_SELF_CLOSE_IN_ATTR !== false;
			SAFE_FOR_TEMPLATES = cfg.SAFE_FOR_TEMPLATES || false;
			SAFE_FOR_XML = cfg.SAFE_FOR_XML !== false;
			WHOLE_DOCUMENT = cfg.WHOLE_DOCUMENT || false;
			RETURN_DOM = cfg.RETURN_DOM || false;
			RETURN_DOM_FRAGMENT = cfg.RETURN_DOM_FRAGMENT || false;
			RETURN_TRUSTED_TYPE = cfg.RETURN_TRUSTED_TYPE || false;
			FORCE_BODY = cfg.FORCE_BODY || false;
			SANITIZE_DOM = cfg.SANITIZE_DOM !== false;
			SANITIZE_NAMED_PROPS = cfg.SANITIZE_NAMED_PROPS || false;
			KEEP_CONTENT = cfg.KEEP_CONTENT !== false;
			IN_PLACE = cfg.IN_PLACE || false;
			IS_ALLOWED_URI$1 = isRegex(cfg.ALLOWED_URI_REGEXP) ? cfg.ALLOWED_URI_REGEXP : IS_ALLOWED_URI;
			NAMESPACE = typeof cfg.NAMESPACE === "string" ? cfg.NAMESPACE : HTML_NAMESPACE;
			MATHML_TEXT_INTEGRATION_POINTS = objectHasOwnProperty(cfg, "MATHML_TEXT_INTEGRATION_POINTS") && cfg.MATHML_TEXT_INTEGRATION_POINTS && typeof cfg.MATHML_TEXT_INTEGRATION_POINTS === "object" ? clone(cfg.MATHML_TEXT_INTEGRATION_POINTS) : addToSet({}, DEFAULT_MATHML_TEXT_INTEGRATION_POINTS);
			HTML_INTEGRATION_POINTS = objectHasOwnProperty(cfg, "HTML_INTEGRATION_POINTS") && cfg.HTML_INTEGRATION_POINTS && typeof cfg.HTML_INTEGRATION_POINTS === "object" ? clone(cfg.HTML_INTEGRATION_POINTS) : addToSet({}, DEFAULT_HTML_INTEGRATION_POINTS);
			const customElementHandling = objectHasOwnProperty(cfg, "CUSTOM_ELEMENT_HANDLING") && cfg.CUSTOM_ELEMENT_HANDLING && typeof cfg.CUSTOM_ELEMENT_HANDLING === "object" ? clone(cfg.CUSTOM_ELEMENT_HANDLING) : create(null);
			CUSTOM_ELEMENT_HANDLING = create(null);
			if (objectHasOwnProperty(customElementHandling, "tagNameCheck") && isRegexOrFunction(customElementHandling.tagNameCheck)) CUSTOM_ELEMENT_HANDLING.tagNameCheck = customElementHandling.tagNameCheck;
			if (objectHasOwnProperty(customElementHandling, "attributeNameCheck") && isRegexOrFunction(customElementHandling.attributeNameCheck)) CUSTOM_ELEMENT_HANDLING.attributeNameCheck = customElementHandling.attributeNameCheck;
			if (objectHasOwnProperty(customElementHandling, "allowCustomizedBuiltInElements") && typeof customElementHandling.allowCustomizedBuiltInElements === "boolean") CUSTOM_ELEMENT_HANDLING.allowCustomizedBuiltInElements = customElementHandling.allowCustomizedBuiltInElements;
			seal(CUSTOM_ELEMENT_HANDLING);
			if (SAFE_FOR_TEMPLATES) ALLOW_DATA_ATTR = false;
			if (RETURN_DOM_FRAGMENT) RETURN_DOM = true;
			if (USE_PROFILES) {
				ALLOWED_TAGS = addToSet({}, text);
				ALLOWED_ATTR = create(null);
				if (USE_PROFILES.html === true) {
					addToSet(ALLOWED_TAGS, html$1);
					addToSet(ALLOWED_ATTR, html);
				}
				if (USE_PROFILES.svg === true) {
					addToSet(ALLOWED_TAGS, svg$1);
					addToSet(ALLOWED_ATTR, svg);
					addToSet(ALLOWED_ATTR, xml);
				}
				if (USE_PROFILES.svgFilters === true) {
					addToSet(ALLOWED_TAGS, svgFilters);
					addToSet(ALLOWED_ATTR, svg);
					addToSet(ALLOWED_ATTR, xml);
				}
				if (USE_PROFILES.mathMl === true) {
					addToSet(ALLOWED_TAGS, mathMl$1);
					addToSet(ALLOWED_ATTR, mathMl);
					addToSet(ALLOWED_ATTR, xml);
				}
			}
			EXTRA_ELEMENT_HANDLING.tagCheck = null;
			EXTRA_ELEMENT_HANDLING.attributeCheck = null;
			if (objectHasOwnProperty(cfg, "ADD_TAGS")) {
				if (typeof cfg.ADD_TAGS === "function") EXTRA_ELEMENT_HANDLING.tagCheck = cfg.ADD_TAGS;
				else if (arrayIsArray(cfg.ADD_TAGS)) {
					if (ALLOWED_TAGS === DEFAULT_ALLOWED_TAGS) ALLOWED_TAGS = clone(ALLOWED_TAGS);
					addToSet(ALLOWED_TAGS, cfg.ADD_TAGS, transformCaseFunc);
				}
			}
			if (objectHasOwnProperty(cfg, "ADD_ATTR")) {
				if (typeof cfg.ADD_ATTR === "function") EXTRA_ELEMENT_HANDLING.attributeCheck = cfg.ADD_ATTR;
				else if (arrayIsArray(cfg.ADD_ATTR)) {
					if (ALLOWED_ATTR === DEFAULT_ALLOWED_ATTR) ALLOWED_ATTR = clone(ALLOWED_ATTR);
					addToSet(ALLOWED_ATTR, cfg.ADD_ATTR, transformCaseFunc);
				}
			}
			if (objectHasOwnProperty(cfg, "ADD_URI_SAFE_ATTR") && arrayIsArray(cfg.ADD_URI_SAFE_ATTR)) addToSet(URI_SAFE_ATTRIBUTES, cfg.ADD_URI_SAFE_ATTR, transformCaseFunc);
			if (objectHasOwnProperty(cfg, "FORBID_CONTENTS") && arrayIsArray(cfg.FORBID_CONTENTS)) {
				if (FORBID_CONTENTS === DEFAULT_FORBID_CONTENTS) FORBID_CONTENTS = clone(FORBID_CONTENTS);
				addToSet(FORBID_CONTENTS, cfg.FORBID_CONTENTS, transformCaseFunc);
			}
			if (objectHasOwnProperty(cfg, "ADD_FORBID_CONTENTS") && arrayIsArray(cfg.ADD_FORBID_CONTENTS)) {
				if (FORBID_CONTENTS === DEFAULT_FORBID_CONTENTS) FORBID_CONTENTS = clone(FORBID_CONTENTS);
				addToSet(FORBID_CONTENTS, cfg.ADD_FORBID_CONTENTS, transformCaseFunc);
			}
			if (KEEP_CONTENT) ALLOWED_TAGS["#text"] = true;
			if (WHOLE_DOCUMENT) addToSet(ALLOWED_TAGS, [
				"html",
				"head",
				"body"
			]);
			if (ALLOWED_TAGS.table) {
				addToSet(ALLOWED_TAGS, ["tbody"]);
				delete FORBID_TAGS.tbody;
			}
			if (cfg.TRUSTED_TYPES_POLICY) {
				if (typeof cfg.TRUSTED_TYPES_POLICY.createHTML !== "function") throw typeErrorCreate("TRUSTED_TYPES_POLICY configuration option must provide a \"createHTML\" hook.");
				if (typeof cfg.TRUSTED_TYPES_POLICY.createScriptURL !== "function") throw typeErrorCreate("TRUSTED_TYPES_POLICY configuration option must provide a \"createScriptURL\" hook.");
				const previousTrustedTypesPolicy = trustedTypesPolicy;
				trustedTypesPolicy = cfg.TRUSTED_TYPES_POLICY;
				try {
					emptyHTML = _createTrustedHTML("");
				} catch (error) {
					trustedTypesPolicy = previousTrustedTypesPolicy;
					throw error;
				}
			} else if (cfg.TRUSTED_TYPES_POLICY === null) {
				trustedTypesPolicy = void 0;
				emptyHTML = "";
			} else {
				if (trustedTypesPolicy === void 0) trustedTypesPolicy = _getDefaultTrustedTypesPolicy();
				if (trustedTypesPolicy && typeof emptyHTML === "string") emptyHTML = _createTrustedHTML("");
			}
			if (freeze) freeze(cfg);
			CONFIG = cfg;
		};
		const ALL_SVG_TAGS = addToSet({}, [
			...svg$1,
			...svgFilters,
			...svgDisallowed
		]);
		const ALL_MATHML_TAGS = addToSet({}, [...mathMl$1, ...mathMlDisallowed]);
		/**
		* Namespace rules for an element in the SVG namespace.
		*
		* @param tagName the element's lowercase tag name
		* @param parent the (possibly simulated) parent node
		* @param parentTagName the parent's lowercase tag name
		* @returns true if a spec-compliant parser could produce this element
		*/
		const _checkSvgNamespace = function _checkSvgNamespace(tagName, parent, parentTagName) {
			if (parent.namespaceURI === HTML_NAMESPACE) return tagName === "svg";
			if (parent.namespaceURI === MATHML_NAMESPACE) return tagName === "svg" && (parentTagName === "annotation-xml" || MATHML_TEXT_INTEGRATION_POINTS[parentTagName]);
			return Boolean(ALL_SVG_TAGS[tagName]);
		};
		/**
		* Namespace rules for an element in the MathML namespace.
		*
		* @param tagName the element's lowercase tag name
		* @param parent the (possibly simulated) parent node
		* @param parentTagName the parent's lowercase tag name
		* @returns true if a spec-compliant parser could produce this element
		*/
		const _checkMathMlNamespace = function _checkMathMlNamespace(tagName, parent, parentTagName) {
			if (parent.namespaceURI === HTML_NAMESPACE) return tagName === "math";
			if (parent.namespaceURI === SVG_NAMESPACE) return tagName === "math" && HTML_INTEGRATION_POINTS[parentTagName];
			return Boolean(ALL_MATHML_TAGS[tagName]);
		};
		/**
		* Namespace rules for an element in the HTML namespace.
		*
		* @param tagName the element's lowercase tag name
		* @param parent the (possibly simulated) parent node
		* @param parentTagName the parent's lowercase tag name
		* @returns true if a spec-compliant parser could produce this element
		*/
		const _checkHtmlNamespace = function _checkHtmlNamespace(tagName, parent, parentTagName) {
			if (parent.namespaceURI === SVG_NAMESPACE && !HTML_INTEGRATION_POINTS[parentTagName]) return false;
			if (parent.namespaceURI === MATHML_NAMESPACE && !MATHML_TEXT_INTEGRATION_POINTS[parentTagName]) return false;
			return !ALL_MATHML_TAGS[tagName] && (COMMON_SVG_AND_HTML_ELEMENTS[tagName] || !ALL_SVG_TAGS[tagName]);
		};
		/**
		* @param element a DOM element whose namespace is being checked
		* @returns Return false if the element has a
		*  namespace that a spec-compliant parser would never
		*  return. Return true otherwise.
		*/
		const _checkValidNamespace = function _checkValidNamespace(element) {
			let parent = getParentNode(element);
			if (!parent || !parent.tagName) parent = {
				namespaceURI: NAMESPACE,
				tagName: "template"
			};
			const tagName = stringToLowerCase(element.tagName);
			const parentTagName = stringToLowerCase(parent.tagName);
			if (!ALLOWED_NAMESPACES[element.namespaceURI]) return false;
			if (element.namespaceURI === SVG_NAMESPACE) return _checkSvgNamespace(tagName, parent, parentTagName);
			if (element.namespaceURI === MATHML_NAMESPACE) return _checkMathMlNamespace(tagName, parent, parentTagName);
			if (element.namespaceURI === HTML_NAMESPACE) return _checkHtmlNamespace(tagName, parent, parentTagName);
			if (PARSER_MEDIA_TYPE === "application/xhtml+xml" && ALLOWED_NAMESPACES[element.namespaceURI]) return true;
			return false;
		};
		/**
		* _forceRemove
		*
		* @param node a DOM node
		*/
		const _forceRemove = function _forceRemove(node) {
			arrayPush(DOMPurify.removed, { element: node });
			try {
				getParentNode(node).removeChild(node);
			} catch (_) {
				remove(node);
				if (!getParentNode(node)) throw typeErrorCreate("a node selected for removal could not be detached from its tree and cannot be safely returned; refusing to sanitize in place");
			}
		};
		/**
		* _neutralizeRoot
		*
		* Fail-closed teardown of an in-place root after the sanitize walk aborts
		* (campaign-3 F2). An internal throw mid-walk — e.g. a page-registered
		* custom element's reaction detaches a node so `_forceRemove`'s deliberate
		* parentless guard throws, or any other re-entrant engine mutation — would
		* otherwise leave the caller's *live* tree half-sanitized, with everything
		* after the abort point still carrying its handlers. There is no safe way
		* to resume the walk (the tree mutated under us), so we strip the root bare:
		* remove every child and every attribute, then let the caller's catch see
		* the original error. Clobber-safe (cached `remove`/`childNodes`/`attributes`
		* getters; the root was already clobber-pre-flighted at the IN_PLACE entry).
		*
		* @param root the in-place root to empty
		*/
		const _neutralizeRoot = function _neutralizeRoot(root) {
			_neutralizeSubtree(root);
			const childNodes = getChildNodes(root);
			if (childNodes) {
				const snapshot = [];
				arrayForEach(childNodes, (child) => {
					arrayPush(snapshot, child);
				});
				arrayForEach(snapshot, (child) => {
					try {
						remove(child);
					} catch (_) {}
				});
			}
			const attributes = getAttributes(root);
			if (attributes) for (let i = attributes.length - 1; i >= 0; --i) {
				const attribute = attributes[i];
				const name = attribute && attribute.name;
				if (typeof name === "string") try {
					root.removeAttribute(name);
				} catch (_) {}
			}
		};
		/**
		* _removeAttribute
		*
		* @param name an Attribute name
		* @param element a DOM node
		*/
		const _removeAttribute = function _removeAttribute(name, element) {
			try {
				arrayPush(DOMPurify.removed, {
					attribute: element.getAttributeNode(name),
					from: element
				});
			} catch (_) {
				arrayPush(DOMPurify.removed, {
					attribute: null,
					from: element
				});
			}
			element.removeAttribute(name);
			if (name === "is") if (RETURN_DOM || RETURN_DOM_FRAGMENT) try {
				_forceRemove(element);
			} catch (_) {}
			else try {
				element.setAttribute(name, "");
			} catch (_) {}
		};
		/**
		* _stripDisallowedAttributes
		*
		* Removes every attribute the active configuration does not allow from a
		* single element, using the same allowlist as the main attribute pass (so
		* `on*` handlers go, but no `/^on/` blocklist is introduced). Used only to
		* neutralise nodes that are being discarded from an in-place tree.
		*
		* @param element the element to strip
		*/
		const _stripDisallowedAttributes = function _stripDisallowedAttributes(element) {
			const attributes = getAttributes(element);
			if (!attributes) return;
			for (let i = attributes.length - 1; i >= 0; --i) {
				const attribute = attributes[i];
				const name = attribute && attribute.name;
				if (typeof name !== "string" || ALLOWED_ATTR[transformCaseFunc(name)]) continue;
				try {
					element.removeAttribute(name);
				} catch (_) {}
			}
		};
		/**
		* _neutralizeSubtree
		*
		* Completes the audit-5 F1 fix across every removal path. The KEEP_CONTENT
		* move-hoist neutralises only disallowed-tag removals; clobber, mXSS-canary,
		* namespace, comment, processing-instruction and KEEP_CONTENT:false removals
		* all drop their subtree wholesale via `_forceRemove`. On the IN_PLACE path
		* those dropped nodes are detached from the caller's LIVE tree but a
		* handler-bearing original among them (an `<img onerror>`/`<video>` that was
		* loading) keeps its queued resource event, which fires in page scope after
		* sanitize returns. This walks a removed subtree and strips every attribute
		* the active configuration does not allow — so `on*` handlers are cancelled
		* through the SAME allowlist that governs kept nodes, not a separate `/^on/`
		* blocklist. Run synchronously before sanitize returns, i.e. before any
		* queued event can fire. Hook-free by design: these nodes leave the output,
		* so firing attribute hooks for them would be surprising. Clobber-safe reads;
		* a doomed clobbered node may shadow `removeAttribute` (its own attributes are
		* irrelevant — it is discarded — while its non-clobbered descendants, e.g.
		* the `<img>`, are reached and scrubbed).
		*
		* @param root the root of a removed subtree to neutralise
		*/
		const _neutralizeSubtree = function _neutralizeSubtree(root) {
			const stack = [root];
			while (stack.length > 0) {
				const node = stack.pop();
				if ((getNodeType ? getNodeType(node) : node.nodeType) === NODE_TYPE.element) _stripDisallowedAttributes(node);
				const childNodes = getChildNodes(node);
				if (childNodes) for (let i = childNodes.length - 1; i >= 0; --i) stack.push(childNodes[i]);
			}
		};
		/**
		* _neutralizePatchLinkage
		*
		* IN_PLACE entry pre-pass (declarative-partial-updates / streaming
		* hardening, https://github.com/WICG/declarative-partial-updates).
		*
		* The main walk strips patch linkage (`for`/`patchsrc`) and removes range
		* markers (PIs / markup comments) node-by-node, in document order, AS it
		* reaches each node. On a live in-place root that leaves a window: from the
		* moment the root is connected until the walk arrives at a given node, that
		* node's linkage is live. A patch applied on connection/stream can fire as
		* a microtask during the walk and inject or teleport an unsanitized DOM
		* range into a region the iterator has already passed and will not revisit,
		* so the post-return "tree is sanitized" contract is violated. Sweep the
		* whole tree once up front and sever every linkage before the walk begins,
		* closing that window.
		*
		* This CANNOT undo a patch that already fired before sanitize ran — that is
		* the irreducible "do not IN_PLACE a live-connected attacker tree" caveat —
		* but it closes everything from sanitize-start onward. Gated on SAFE_FOR_XML
		* to group with the rest of the declarative-partial-updates handling and
		* stay overridable, consistent with the codebase.
		*
		* Clobber-safe traversal (cached childNodes getter); per-node try/catch so a
		* clobbered root cannot defeat the sweep of its non-clobbered descendants.
		*
		* NOTE (pending real-Chrome confirmation, see test/declarative-patch-probe
		* .html Q1): this mirrors the existing policy of keeping `for` on
		* <label>/<output>. If the shipping feature can drive a patch through a
		* surviving `for`-on-label/output + `id` pair, this pre-pass and the
		* attribute check at _isBasicCustomElement's caller must additionally drop
		* that pair on the IN_PLACE path. Left as-is until the taxonomy is verified.
		*
		* @param root the in-place root to sweep
		*/
		const _neutralizePatchLinkage = function _neutralizePatchLinkage(root) {
			if (!SAFE_FOR_XML) return;
			const stack = [root];
			while (stack.length > 0) {
				const node = stack.pop();
				const nodeType = getNodeType ? getNodeType(node) : node.nodeType;
				if (nodeType === NODE_TYPE.processingInstruction || nodeType === NODE_TYPE.comment && regExpTest(COMMENT_MARKUP_PROBE, node.data)) {
					try {
						remove(node);
					} catch (_) {}
					continue;
				}
				if (nodeType === NODE_TYPE.element) {
					const element = node;
					const lcTag = transformCaseFunc(getNodeName ? getNodeName(node) : node.nodeName);
					try {
						if (element.hasAttribute && element.hasAttribute("patchsrc")) element.removeAttribute("patchsrc");
						if (element.hasAttribute && element.hasAttribute("for") && lcTag !== "label" && lcTag !== "output") element.removeAttribute("for");
					} catch (_) {}
				}
				const childNodes = getChildNodes(node);
				if (childNodes) for (let i = childNodes.length - 1; i >= 0; --i) stack.push(childNodes[i]);
			}
		};
		/**
		* _initDocument
		*
		* @param dirty - a string of dirty markup
		* @return a DOM, filled with the dirty markup
		*/
		const _initDocument = function _initDocument(dirty) {
			let doc = null;
			let leadingWhitespace = null;
			if (FORCE_BODY) dirty = "<remove></remove>" + dirty;
			else {
				const matches = stringMatch(dirty, /^[\r\n\t ]+/);
				leadingWhitespace = matches && matches[0];
			}
			if (PARSER_MEDIA_TYPE === "application/xhtml+xml" && NAMESPACE === HTML_NAMESPACE) dirty = "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head></head><body>" + dirty + "</body></html>";
			const dirtyPayload = trustedTypesPolicy ? _createTrustedHTML(dirty) : dirty;
			if (NAMESPACE === HTML_NAMESPACE) try {
				doc = new DOMParser().parseFromString(dirtyPayload, PARSER_MEDIA_TYPE);
			} catch (_) {}
			if (!doc || !doc.documentElement) {
				doc = implementation.createDocument(NAMESPACE, "template", null);
				try {
					doc.documentElement.innerHTML = IS_EMPTY_INPUT ? emptyHTML : dirtyPayload;
				} catch (_) {}
			}
			const body = doc.body || doc.documentElement;
			if (dirty && leadingWhitespace) body.insertBefore(document.createTextNode(leadingWhitespace), body.childNodes[0] || null);
			if (NAMESPACE === HTML_NAMESPACE) return getElementsByTagName.call(doc, WHOLE_DOCUMENT ? "html" : "body")[0];
			return WHOLE_DOCUMENT ? doc.documentElement : body;
		};
		/**
		* Creates a NodeIterator object that you can use to traverse filtered lists of nodes or elements in a document.
		*
		* @param root The root element or node to start traversing on.
		* @return The created NodeIterator
		*/
		const _createNodeIterator = function _createNodeIterator(root) {
			return createNodeIterator.call(root.ownerDocument || root, root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_COMMENT | NodeFilter.SHOW_TEXT | NodeFilter.SHOW_PROCESSING_INSTRUCTION | NodeFilter.SHOW_CDATA_SECTION, null);
		};
		/**
		* Replace template expression syntax (mustache, ERB, template
		* literal) with a space; shared by all SAFE_FOR_TEMPLATES scrub
		* sites. Order matters: mustache, then ERB, then template literal.
		*
		* @param value the string to scrub
		* @returns the scrubbed string
		*/
		const _stripTemplateExpressions = function _stripTemplateExpressions(value) {
			value = stringReplace(value, MUSTACHE_EXPR$1, " ");
			value = stringReplace(value, ERB_EXPR$1, " ");
			value = stringReplace(value, TMPLIT_EXPR$1, " ");
			return value;
		};
		/**
		* Strip template-engine expressions ({{...}}, ${...}, <%...%>) from the
		* character data of an element subtree. Used as the final safety net for
		* SAFE_FOR_TEMPLATES on every DOM-returning code path so that expressions
		* which only form after text-node normalization (e.g. fragments split across
		* stripped elements) cannot survive into a template-evaluating framework.
		*
		* Walks text/comment/CDATA/processing-instruction nodes and mutates `.data`
		* in place rather than round-tripping through innerHTML. This preserves
		* descendant node references (important for IN_PLACE callers), avoids a
		* serialize/reparse cycle, and reads literal character data — which means
		* `<%...%>` in text content matches the ERB regex against its real bytes
		* instead of the HTML-entity-escaped form innerHTML would produce.
		*
		* Attribute values are not visited here; SAFE_FOR_TEMPLATES handling for
		* attributes is performed during the per-node `_sanitizeAttributes` pass.
		*
		* @param node The root element whose character data should be scrubbed.
		*/
		const _scrubTemplateExpressions2 = function _scrubTemplateExpressions(node) {
			var _node$querySelectorAl;
			node.normalize();
			const walker = createNodeIterator.call(node.ownerDocument || node, node, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_COMMENT | NodeFilter.SHOW_CDATA_SECTION | NodeFilter.SHOW_PROCESSING_INSTRUCTION, null);
			let currentNode = walker.nextNode();
			while (currentNode) {
				currentNode.data = _stripTemplateExpressions(currentNode.data);
				currentNode = walker.nextNode();
			}
			const templates = (_node$querySelectorAl = node.querySelectorAll) === null || _node$querySelectorAl === void 0 ? void 0 : _node$querySelectorAl.call(node, "template");
			if (templates) arrayForEach(templates, (tmpl) => {
				if (_isDocumentFragment(tmpl.content)) _scrubTemplateExpressions2(tmpl.content);
			});
		};
		/**
		* _isClobbered
		*
		* Detect DOM-clobbering on HTMLFormElement nodes. Form is the only HTML
		* interface with [LegacyOverrideBuiltIns]; a descendant element with a
		* `name` attribute matching a prototype property shadows that property
		* on direct reads. We use this check at the IN_PLACE entry-point and
		* during attribute sanitization to refuse clobbered forms.
		*
		* @param element element to check for clobbering attacks
		* @return true if clobbered, false if safe
		*/
		const _isClobbered = function _isClobbered(element) {
			const realTagName = getNodeName ? getNodeName(element) : null;
			if (typeof realTagName !== "string") return false;
			if (transformCaseFunc(realTagName) !== "form") return false;
			return typeof element.nodeName !== "string" || typeof element.textContent !== "string" || typeof element.removeChild !== "function" || element.attributes !== getAttributes(element) || typeof element.removeAttribute !== "function" || typeof element.setAttribute !== "function" || typeof element.namespaceURI !== "string" || typeof element.insertBefore !== "function" || typeof element.hasChildNodes !== "function" || element.nodeType !== getNodeType(element) || element.childNodes !== getChildNodes(element);
		};
		/**
		* Checks whether the given value is a DocumentFragment from any realm.
		*
		* The realm-independent replacement reads `nodeType` through the cached
		* Node.prototype getter and compares to the DOCUMENT_FRAGMENT_NODE
		* constant (11). nodeType is a numeric value resolved from the node's
		* internal slot, identical across realms for the same kind of node.
		*
		* @param value object to check
		* @return true if value is a DocumentFragment-shaped node from any realm
		*/
		const _isDocumentFragment = function _isDocumentFragment(value) {
			if (!getNodeType || typeof value !== "object" || value === null) return false;
			try {
				return getNodeType(value) === NODE_TYPE.documentFragment;
			} catch (_) {
				return false;
			}
		};
		/**
		* Checks whether the given object is a DOM node, including nodes that
		* originate from a different window/realm (e.g. an iframe's
		* contentDocument). The previous `value instanceof Node` check was
		* realm-bound: nodes from a different window failed it, causing
		* sanitize() to silently stringify them and reset IN_PLACE to false,
		* returning the original node unsanitized. See GHSA-4w3q-35jp-p934.
		*
		* @param value object to check whether it's a DOM node
		* @return true if value is a DOM node from any realm
		*/
		const _isNode = function _isNode(value) {
			if (!getNodeType || typeof value !== "object" || value === null) return false;
			try {
				return typeof getNodeType(value) === "number";
			} catch (_) {
				return false;
			}
		};
		function _executeHooks(hooks, currentNode, data) {
			if (hooks.length === 0) return;
			arrayForEach(hooks, (hook) => {
				hook.call(DOMPurify, currentNode, data, CONFIG);
			});
		}
		/**
		* Structural-threat checks that condemn a node regardless of the
		* allowlists: mXSS via namespace confusion, risky CSS construction,
		* processing instructions, markup-bearing comments. Pure predicate;
		* the caller removes. Check order is load-bearing.
		*
		* @param currentNode the node to inspect
		* @param tagName the node's transformCaseFunc'd tag name
		* @return true if the node must be removed
		*/
		const _isUnsafeNode = function _isUnsafeNode(currentNode, tagName) {
			if (SAFE_FOR_XML && currentNode.hasChildNodes() && !_isNode(currentNode.firstElementChild) && regExpTest(ELEMENT_MARKUP_PROBE, currentNode.textContent) && regExpTest(ELEMENT_MARKUP_PROBE, currentNode.innerHTML)) return true;
			if (SAFE_FOR_XML && currentNode.namespaceURI === HTML_NAMESPACE && tagName === "style" && _isNode(currentNode.firstElementChild)) return true;
			if (currentNode.nodeType === NODE_TYPE.processingInstruction) return true;
			if (SAFE_FOR_XML && currentNode.nodeType === NODE_TYPE.comment && regExpTest(COMMENT_MARKUP_PROBE, currentNode.data)) return true;
			return false;
		};
		/**
		* Handle a node whose tag is forbidden or not allowlisted: keep
		* allowed custom elements (false return exits _sanitizeElements
		* early - the namespace and fallback-tag removal checks are
		* intentionally skipped for kept custom elements), else hoist
		* content per KEEP_CONTENT and remove.
		*
		* A kept custom element is the ONLY case in which this function
		* returns false, so the caller uses that return value to run the
		* afterSanitizeElements hook on the kept element and keep the
		* element-hook lifecycle consistent with normal allowlisted
		* elements (GHSA-c2j3-45gr-mqc4).
		*
		* @param currentNode the disallowed node
		* @param tagName the node's transformCaseFunc'd tag name
		* @return true if the node was removed, false if kept
		*/
		const _sanitizeDisallowedNode = function _sanitizeDisallowedNode(currentNode, tagName) {
			if (!FORBID_TAGS[tagName] && _isBasicCustomElement(tagName)) {
				if (CUSTOM_ELEMENT_HANDLING.tagNameCheck instanceof RegExp && regExpTest(CUSTOM_ELEMENT_HANDLING.tagNameCheck, tagName)) return false;
				if (CUSTOM_ELEMENT_HANDLING.tagNameCheck instanceof Function && CUSTOM_ELEMENT_HANDLING.tagNameCheck(tagName)) return false;
			}
			if (KEEP_CONTENT && !FORBID_CONTENTS[tagName]) {
				const parentNode = getParentNode(currentNode);
				const childNodes = getChildNodes(currentNode);
				if (childNodes && parentNode) {
					const childCount = childNodes.length;
					for (let i = childCount - 1; i >= 0; --i) {
						const hoisted = IN_PLACE ? childNodes[i] : cloneNode(childNodes[i], true);
						parentNode.insertBefore(hoisted, getNextSibling(currentNode));
					}
				}
			}
			_forceRemove(currentNode);
			return true;
		};
		/**
		* _sanitizeElements
		*
		* @protect nodeName
		* @protect textContent
		* @protect removeChild
		* @param currentNode to check for permission to exist
		* @return true if node was killed, false if left alive
		*/
		const _sanitizeElements = function _sanitizeElements(currentNode, root) {
			_executeHooks(hooks.beforeSanitizeElements, currentNode, null);
			if (currentNode !== root && getParentNode(currentNode) === null) return true;
			if (_isClobbered(currentNode)) {
				_forceRemove(currentNode);
				return true;
			}
			const tagName = transformCaseFunc(getNodeName ? getNodeName(currentNode) : currentNode.nodeName);
			_executeHooks(hooks.uponSanitizeElement, currentNode, {
				tagName,
				allowedTags: ALLOWED_TAGS
			});
			if (currentNode !== root && getParentNode(currentNode) === null) return true;
			if (_isUnsafeNode(currentNode, tagName)) {
				_forceRemove(currentNode);
				return true;
			}
			if (FORBID_TAGS[tagName] || !(EXTRA_ELEMENT_HANDLING.tagCheck instanceof Function && EXTRA_ELEMENT_HANDLING.tagCheck(tagName)) && !ALLOWED_TAGS[tagName]) {
				const removed = _sanitizeDisallowedNode(currentNode, tagName);
				if (removed === false) _executeHooks(hooks.afterSanitizeElements, currentNode, null);
				return removed;
			}
			if ((getNodeType ? getNodeType(currentNode) : currentNode.nodeType) === NODE_TYPE.element && !_checkValidNamespace(currentNode)) {
				_forceRemove(currentNode);
				return true;
			}
			if ((tagName === "noscript" || tagName === "noembed" || tagName === "noframes") && regExpTest(FALLBACK_TAG_CLOSE, currentNode.innerHTML)) {
				_forceRemove(currentNode);
				return true;
			}
			if (SAFE_FOR_TEMPLATES && currentNode.nodeType === NODE_TYPE.text) {
				const content = _stripTemplateExpressions(currentNode.textContent);
				if (currentNode.textContent !== content) {
					arrayPush(DOMPurify.removed, { element: currentNode.cloneNode() });
					currentNode.textContent = content;
				}
			}
			_executeHooks(hooks.afterSanitizeElements, currentNode, null);
			return false;
		};
		/**
		* _isValidAttribute
		*
		* @param lcTag Lowercase tag name of containing element.
		* @param lcName Lowercase attribute name.
		* @param value Attribute value.
		* @return Returns true if `value` is valid, otherwise false.
		*/
		const _isValidAttribute = function _isValidAttribute(lcTag, lcName, value) {
			if (FORBID_ATTR[lcName]) return false;
			if (SAFE_FOR_XML && lcName === "patchsrc") return false;
			if (SAFE_FOR_XML && lcName === "for" && lcTag !== "label" && lcTag !== "output") return false;
			if (SANITIZE_DOM && (lcName === "id" || lcName === "name") && (value in document || value in formElement)) return false;
			const nameIsPermitted = ALLOWED_ATTR[lcName] || EXTRA_ELEMENT_HANDLING.attributeCheck instanceof Function && EXTRA_ELEMENT_HANDLING.attributeCheck(lcName, lcTag);
			if (ALLOW_DATA_ATTR && regExpTest(DATA_ATTR$1, lcName));
			else if (ALLOW_ARIA_ATTR && regExpTest(ARIA_ATTR$1, lcName));
			else if (!nameIsPermitted) if (_isBasicCustomElement(lcTag) && (CUSTOM_ELEMENT_HANDLING.tagNameCheck instanceof RegExp && regExpTest(CUSTOM_ELEMENT_HANDLING.tagNameCheck, lcTag) || CUSTOM_ELEMENT_HANDLING.tagNameCheck instanceof Function && CUSTOM_ELEMENT_HANDLING.tagNameCheck(lcTag)) && (CUSTOM_ELEMENT_HANDLING.attributeNameCheck instanceof RegExp && regExpTest(CUSTOM_ELEMENT_HANDLING.attributeNameCheck, lcName) || CUSTOM_ELEMENT_HANDLING.attributeNameCheck instanceof Function && CUSTOM_ELEMENT_HANDLING.attributeNameCheck(lcName, lcTag)) || lcName === "is" && CUSTOM_ELEMENT_HANDLING.allowCustomizedBuiltInElements && (CUSTOM_ELEMENT_HANDLING.tagNameCheck instanceof RegExp && regExpTest(CUSTOM_ELEMENT_HANDLING.tagNameCheck, value) || CUSTOM_ELEMENT_HANDLING.tagNameCheck instanceof Function && CUSTOM_ELEMENT_HANDLING.tagNameCheck(value)));
			else return false;
			else if (URI_SAFE_ATTRIBUTES[lcName]);
			else if (regExpTest(IS_ALLOWED_URI$1, stringReplace(value, ATTR_WHITESPACE$1, "")));
			else if ((lcName === "src" || lcName === "xlink:href" || lcName === "href") && lcTag !== "script" && stringIndexOf(value, "data:") === 0 && DATA_URI_TAGS[lcTag]);
			else if (ALLOW_UNKNOWN_PROTOCOLS && !regExpTest(IS_SCRIPT_OR_DATA$1, stringReplace(value, ATTR_WHITESPACE$1, "")));
			else if (value) return false;
			return true;
		};
		const RESERVED_CUSTOM_ELEMENT_NAMES = addToSet({}, [
			"annotation-xml",
			"color-profile",
			"font-face",
			"font-face-format",
			"font-face-name",
			"font-face-src",
			"font-face-uri",
			"missing-glyph"
		]);
		/**
		* _isBasicCustomElement
		* checks if at least one dash is included in tagName, and it's not the first char
		* for more sophisticated checking see https://github.com/sindresorhus/validate-element-name
		*
		* @param tagName name of the tag of the node to sanitize
		* @returns Returns true if the tag name meets the basic criteria for a custom element, otherwise false.
		*/
		const _isBasicCustomElement = function _isBasicCustomElement(tagName) {
			return !RESERVED_CUSTOM_ELEMENT_NAMES[stringToLowerCase(tagName)] && regExpTest(CUSTOM_ELEMENT$1, tagName);
		};
		/**
		* Wrap an attribute value in the matching Trusted Types object when
		* the active policy requires it. Namespaced attributes pass through
		* unchanged (no TT support yet, see
		* https://bugs.chromium.org/p/chromium/issues/detail?id=1305293).
		*
		* @param lcTag lowercase tag name of the containing element
		* @param lcName lowercase attribute name
		* @param namespaceURI the attribute's namespace, if any
		* @param value the attribute value to wrap
		* @return the value, wrapped when Trusted Types demand it
		*/
		const _applyTrustedTypesToAttribute = function _applyTrustedTypesToAttribute(lcTag, lcName, namespaceURI, value) {
			if (trustedTypesPolicy && typeof trustedTypes === "object" && typeof trustedTypes.getAttributeType === "function" && !namespaceURI) switch (trustedTypes.getAttributeType(lcTag, lcName)) {
				case "TrustedHTML": return _createTrustedHTML(value);
				case "TrustedScriptURL": return _createTrustedScriptURL(value);
			}
			return value;
		};
		/**
		* Write a modified attribute value back onto the element. On
		* success, re-probe for clobbering introduced by the new value and
		* remove the element when found; otherwise pop the removal entry
		* recorded by the earlier _removeAttribute (long-standing pairing
		* with the SANITIZE_NAMED_PROPS path - do not "fix" casually). On
		* failure, remove the attribute instead.
		*
		* @param currentNode the element carrying the attribute
		* @param name the attribute name as present on the element
		* @param namespaceURI the attribute's namespace, if any
		* @param value the new attribute value
		*/
		const _setAttributeValue = function _setAttributeValue(currentNode, name, namespaceURI, value) {
			try {
				if (namespaceURI) currentNode.setAttributeNS(namespaceURI, name, value);
				else currentNode.setAttribute(name, value);
				if (_isClobbered(currentNode)) _forceRemove(currentNode);
				else arrayPop(DOMPurify.removed);
			} catch (_) {
				_removeAttribute(name, currentNode);
			}
		};
		/**
		* _sanitizeAttributes
		*
		* @protect attributes
		* @protect nodeName
		* @protect removeAttribute
		* @protect setAttribute
		*
		* @param currentNode to sanitize
		*/
		const _sanitizeAttributes = function _sanitizeAttributes(currentNode) {
			_executeHooks(hooks.beforeSanitizeAttributes, currentNode, null);
			const attributes = currentNode.attributes;
			if (!attributes || _isClobbered(currentNode)) return;
			const hookEvent = {
				attrName: "",
				attrValue: "",
				keepAttr: true,
				allowedAttributes: ALLOWED_ATTR,
				forceKeepAttr: void 0
			};
			let l = attributes.length;
			const lcTag = transformCaseFunc(currentNode.nodeName);
			while (l--) {
				const attr = attributes[l];
				const name = attr.name, namespaceURI = attr.namespaceURI, attrValue = attr.value;
				const lcName = transformCaseFunc(name);
				const initValue = attrValue;
				let value = name === "value" ? initValue : stringTrim(initValue);
				hookEvent.attrName = lcName;
				hookEvent.attrValue = value;
				hookEvent.keepAttr = true;
				hookEvent.forceKeepAttr = void 0;
				_executeHooks(hooks.uponSanitizeAttribute, currentNode, hookEvent);
				value = hookEvent.attrValue;
				if (SANITIZE_NAMED_PROPS && (lcName === "id" || lcName === "name") && stringIndexOf(value, SANITIZE_NAMED_PROPS_PREFIX) !== 0) {
					_removeAttribute(name, currentNode);
					value = SANITIZE_NAMED_PROPS_PREFIX + value;
				}
				if (SAFE_FOR_XML && regExpTest(/((--!?|])>)|<\/(style|script|title|xmp|textarea|noscript|iframe|noembed|noframes)/i, value)) {
					_removeAttribute(name, currentNode);
					continue;
				}
				if (lcName === "attributename" && stringMatch(value, "href")) {
					_removeAttribute(name, currentNode);
					continue;
				}
				if (hookEvent.forceKeepAttr) continue;
				if (!hookEvent.keepAttr) {
					_removeAttribute(name, currentNode);
					continue;
				}
				if (!ALLOW_SELF_CLOSE_IN_ATTR && regExpTest(SELF_CLOSING_TAG, value)) {
					_removeAttribute(name, currentNode);
					continue;
				}
				if (SAFE_FOR_TEMPLATES) value = _stripTemplateExpressions(value);
				if (!_isValidAttribute(lcTag, lcName, value)) {
					_removeAttribute(name, currentNode);
					continue;
				}
				value = _applyTrustedTypesToAttribute(lcTag, lcName, namespaceURI, value);
				if (value !== initValue) _setAttributeValue(currentNode, name, namespaceURI, value);
			}
			_executeHooks(hooks.afterSanitizeAttributes, currentNode, null);
		};
		/**
		* _sanitizeShadowDOM
		*
		* @param fragment to iterate over recursively
		*/
		const _sanitizeShadowDOM2 = function _sanitizeShadowDOM(fragment) {
			let shadowNode = null;
			const shadowIterator = _createNodeIterator(fragment);
			_executeHooks(hooks.beforeSanitizeShadowDOM, fragment, null);
			while (shadowNode = shadowIterator.nextNode()) {
				_executeHooks(hooks.uponSanitizeShadowNode, shadowNode, null);
				_sanitizeElements(shadowNode, fragment);
				_sanitizeAttributes(shadowNode);
				if (_isDocumentFragment(shadowNode.content)) _sanitizeShadowDOM2(shadowNode.content);
				if ((getNodeType ? getNodeType(shadowNode) : shadowNode.nodeType) === NODE_TYPE.element) {
					const innerSr = getShadowRoot(shadowNode);
					if (_isDocumentFragment(innerSr)) {
						_sanitizeAttachedShadowRoots(innerSr);
						_sanitizeShadowDOM2(innerSr);
					}
				}
			}
			_executeHooks(hooks.afterSanitizeShadowDOM, fragment, null);
		};
		/**
		* _sanitizeAttachedShadowRoots
		*
		* Walks `root` and feeds every attached shadow root we encounter into
		* the existing _sanitizeShadowDOM pipeline. The default node iterator
		* does not descend into shadow trees, so nodes inside an attached
		* shadow root would otherwise be skipped entirely.
		*
		* Two real input paths put attached shadow roots in front of us:
		*   1. IN_PLACE on a DOM node that already has shadow roots attached.
		*   2. DOM-node input where importNode(dirty, true) deep-clones the
		*      shadow root because it was created with `clonable: true`.
		*
		* This pass runs once, up front, so the main iteration loop (and the
		* existing _sanitizeShadowDOM template-content recursion) stay
		* untouched — string-input paths are not affected.
		*
		* @param root the subtree root to walk for attached shadow roots
		*/
		const _sanitizeAttachedShadowRoots = function _sanitizeAttachedShadowRoots(root) {
			const stack = [{
				node: root,
				shadow: null
			}];
			while (stack.length > 0) {
				const item = stack.pop();
				if (item.shadow) {
					_sanitizeShadowDOM2(item.shadow);
					continue;
				}
				const node = item.node;
				const isElement = (getNodeType ? getNodeType(node) : node.nodeType) === NODE_TYPE.element;
				const childNodes = getChildNodes(node);
				if (childNodes) for (let i = childNodes.length - 1; i >= 0; --i) stack.push({
					node: childNodes[i],
					shadow: null
				});
				if (isElement) {
					const rootName = getNodeName ? getNodeName(node) : null;
					if (typeof rootName === "string" && transformCaseFunc(rootName) === "template") {
						const content = node.content;
						if (_isDocumentFragment(content)) stack.push({
							node: content,
							shadow: null
						});
					}
				}
				if (isElement) {
					const sr = getShadowRoot(node);
					if (_isDocumentFragment(sr)) stack.push({
						node: null,
						shadow: sr
					}, {
						node: sr,
						shadow: null
					});
				}
			}
		};
		DOMPurify.sanitize = function(dirty) {
			let cfg = arguments.length > 1 && arguments[1] !== void 0 ? arguments[1] : {};
			let body = null;
			let importedNode = null;
			let currentNode = null;
			let returnNode = null;
			IS_EMPTY_INPUT = !dirty;
			if (IS_EMPTY_INPUT) dirty = "<!-->";
			if (typeof dirty !== "string" && !_isNode(dirty)) {
				dirty = stringifyValue(dirty);
				if (typeof dirty !== "string") throw typeErrorCreate("dirty is not a string, aborting");
			}
			if (!DOMPurify.isSupported) return dirty;
			if (SET_CONFIG) {
				ALLOWED_TAGS = SET_CONFIG_ALLOWED_TAGS;
				ALLOWED_ATTR = SET_CONFIG_ALLOWED_ATTR;
			} else _parseConfig(cfg);
			if (hooks.uponSanitizeElement.length > 0 || hooks.uponSanitizeAttribute.length > 0) ALLOWED_TAGS = clone(ALLOWED_TAGS);
			if (hooks.uponSanitizeAttribute.length > 0) ALLOWED_ATTR = clone(ALLOWED_ATTR);
			DOMPurify.removed = [];
			const inPlace = IN_PLACE && typeof dirty !== "string" && _isNode(dirty);
			if (inPlace) {
				_neutralizePatchLinkage(dirty);
				const nn = getNodeName ? getNodeName(dirty) : dirty.nodeName;
				if (typeof nn === "string") {
					const tagName = transformCaseFunc(nn);
					if (!ALLOWED_TAGS[tagName] || FORBID_TAGS[tagName]) {
						_neutralizeRoot(dirty);
						throw typeErrorCreate("root node is forbidden and cannot be sanitized in-place");
					}
				}
				if (_isClobbered(dirty)) {
					_neutralizeRoot(dirty);
					throw typeErrorCreate("root node is clobbered and cannot be sanitized in-place");
				}
				try {
					_sanitizeAttachedShadowRoots(dirty);
				} catch (error) {
					_neutralizeRoot(dirty);
					throw error;
				}
			} else if (_isNode(dirty)) {
				body = _initDocument("<!---->");
				importedNode = body.ownerDocument.importNode(dirty, true);
				if (importedNode.nodeType === NODE_TYPE.element && importedNode.nodeName === "BODY") body = importedNode;
				else if (importedNode.nodeName === "HTML") body = importedNode;
				else body.appendChild(importedNode);
				_sanitizeAttachedShadowRoots(importedNode);
			} else {
				if (!RETURN_DOM && !SAFE_FOR_TEMPLATES && !WHOLE_DOCUMENT && dirty.indexOf("<") === -1) return trustedTypesPolicy && RETURN_TRUSTED_TYPE ? _createTrustedHTML(dirty) : dirty;
				body = _initDocument(dirty);
				if (!body) return RETURN_DOM ? null : RETURN_TRUSTED_TYPE ? emptyHTML : "";
			}
			if (body && FORCE_BODY) _forceRemove(body.firstChild);
			const walkRoot = inPlace ? dirty : body;
			const nodeIterator = _createNodeIterator(walkRoot);
			try {
				while (currentNode = nodeIterator.nextNode()) {
					_sanitizeElements(currentNode, walkRoot);
					_sanitizeAttributes(currentNode);
					if (_isDocumentFragment(currentNode.content)) _sanitizeShadowDOM2(currentNode.content);
				}
			} catch (error) {
				if (inPlace) {
					_neutralizeRoot(dirty);
					arrayForEach(DOMPurify.removed, (entry) => {
						if (entry.element) _neutralizeSubtree(entry.element);
					});
				}
				throw error;
			}
			if (inPlace) {
				arrayForEach(DOMPurify.removed, (entry) => {
					if (entry.element) _neutralizeSubtree(entry.element);
				});
				if (SAFE_FOR_TEMPLATES) _scrubTemplateExpressions2(dirty);
				return dirty;
			}
			if (RETURN_DOM) {
				if (SAFE_FOR_TEMPLATES) _scrubTemplateExpressions2(body);
				if (RETURN_DOM_FRAGMENT) {
					returnNode = createDocumentFragment.call(body.ownerDocument);
					while (body.firstChild) returnNode.appendChild(body.firstChild);
				} else returnNode = body;
				if (ALLOWED_ATTR.shadowroot || ALLOWED_ATTR.shadowrootmode) returnNode = importNode.call(originalDocument, returnNode, true);
				return returnNode;
			}
			let serializedHTML = WHOLE_DOCUMENT ? body.outerHTML : body.innerHTML;
			if (WHOLE_DOCUMENT && ALLOWED_TAGS["!doctype"] && body.ownerDocument && body.ownerDocument.doctype && body.ownerDocument.doctype.name && regExpTest(DOCTYPE_NAME, body.ownerDocument.doctype.name)) serializedHTML = "<!DOCTYPE " + body.ownerDocument.doctype.name + ">\n" + serializedHTML;
			if (SAFE_FOR_TEMPLATES) serializedHTML = _stripTemplateExpressions(serializedHTML);
			return trustedTypesPolicy && RETURN_TRUSTED_TYPE ? _createTrustedHTML(serializedHTML) : serializedHTML;
		};
		DOMPurify.setConfig = function() {
			_parseConfig(arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : {});
			SET_CONFIG = true;
			SET_CONFIG_ALLOWED_TAGS = ALLOWED_TAGS;
			SET_CONFIG_ALLOWED_ATTR = ALLOWED_ATTR;
		};
		DOMPurify.clearConfig = function() {
			CONFIG = null;
			SET_CONFIG = false;
			SET_CONFIG_ALLOWED_TAGS = null;
			SET_CONFIG_ALLOWED_ATTR = null;
			trustedTypesPolicy = defaultTrustedTypesPolicy;
			emptyHTML = "";
		};
		DOMPurify.isValidAttribute = function(tag, attr, value) {
			if (!CONFIG) _parseConfig({});
			return _isValidAttribute(transformCaseFunc(tag), transformCaseFunc(attr), value);
		};
		DOMPurify.addHook = function(entryPoint, hookFunction) {
			if (typeof hookFunction !== "function") return;
			if (!objectHasOwnProperty(hooks, entryPoint)) return;
			arrayPush(hooks[entryPoint], hookFunction);
		};
		DOMPurify.removeHook = function(entryPoint, hookFunction) {
			if (!objectHasOwnProperty(hooks, entryPoint)) return;
			if (hookFunction !== void 0) {
				const index = arrayLastIndexOf(hooks[entryPoint], hookFunction);
				return index === -1 ? void 0 : arraySplice(hooks[entryPoint], index, 1)[0];
			}
			return arrayPop(hooks[entryPoint]);
		};
		DOMPurify.removeHooks = function(entryPoint) {
			if (!objectHasOwnProperty(hooks, entryPoint)) return;
			hooks[entryPoint] = [];
		};
		DOMPurify.removeAllHooks = function() {
			hooks = _createHooksMap();
		};
		return DOMPurify;
	}
	var purify = createDOMPurify();
	//#endregion
	//#region node_modules/marked/lib/marked.esm.js
	/**
	* marked v17.0.5 - a markdown parser
	* Copyright (c) 2018-2026, MarkedJS. (MIT License)
	* Copyright (c) 2011-2018, Christopher Jeffrey. (MIT License)
	* https://github.com/markedjs/marked
	*/
	/**
	* DO NOT EDIT THIS FILE
	* The code in this file is generated from files in ./src/
	*/
	function M() {
		return {
			async: !1,
			breaks: !1,
			extensions: null,
			gfm: !0,
			hooks: null,
			pedantic: !1,
			renderer: null,
			silent: !1,
			tokenizer: null,
			walkTokens: null
		};
	}
	var T = M();
	function G(u) {
		T = u;
	}
	var _ = { exec: () => null };
	function k(u, e = "") {
		let t = typeof u == "string" ? u : u.source, n = {
			replace: (r, i) => {
				let s = typeof i == "string" ? i : i.source;
				return s = s.replace(m.caret, "$1"), t = t.replace(r, s), n;
			},
			getRegex: () => new RegExp(t, e)
		};
		return n;
	}
	var be = (() => {
		try {
			return true;
		} catch {
			return !1;
		}
	})(), m = {
		codeRemoveIndent: /^(?: {1,4}| {0,3}\t)/gm,
		outputLinkReplace: /\\([\[\]])/g,
		indentCodeCompensation: /^(\s+)(?:```)/,
		beginningSpace: /^\s+/,
		endingHash: /#$/,
		startingSpaceChar: /^ /,
		endingSpaceChar: / $/,
		nonSpaceChar: /[^ ]/,
		newLineCharGlobal: /\n/g,
		tabCharGlobal: /\t/g,
		multipleSpaceGlobal: /\s+/g,
		blankLine: /^[ \t]*$/,
		doubleBlankLine: /\n[ \t]*\n[ \t]*$/,
		blockquoteStart: /^ {0,3}>/,
		blockquoteSetextReplace: /\n {0,3}((?:=+|-+) *)(?=\n|$)/g,
		blockquoteSetextReplace2: /^ {0,3}>[ \t]?/gm,
		listReplaceNesting: /^ {1,4}(?=( {4})*[^ ])/g,
		listIsTask: /^\[[ xX]\] +\S/,
		listReplaceTask: /^\[[ xX]\] +/,
		listTaskCheckbox: /\[[ xX]\]/,
		anyLine: /\n.*\n/,
		hrefBrackets: /^<(.*)>$/,
		tableDelimiter: /[:|]/,
		tableAlignChars: /^\||\| *$/g,
		tableRowBlankLine: /\n[ \t]*$/,
		tableAlignRight: /^ *-+: *$/,
		tableAlignCenter: /^ *:-+: *$/,
		tableAlignLeft: /^ *:-+ *$/,
		startATag: /^<a /i,
		endATag: /^<\/a>/i,
		startPreScriptTag: /^<(pre|code|kbd|script)(\s|>)/i,
		endPreScriptTag: /^<\/(pre|code|kbd|script)(\s|>)/i,
		startAngleBracket: /^</,
		endAngleBracket: />$/,
		pedanticHrefTitle: /^([^'"]*[^\s])\s+(['"])(.*)\2/,
		unicodeAlphaNumeric: /[\p{L}\p{N}]/u,
		escapeTest: /[&<>"']/,
		escapeReplace: /[&<>"']/g,
		escapeTestNoEncode: /[<>"']|&(?!(#\d{1,7}|#[Xx][a-fA-F0-9]{1,6}|\w+);)/,
		escapeReplaceNoEncode: /[<>"']|&(?!(#\d{1,7}|#[Xx][a-fA-F0-9]{1,6}|\w+);)/g,
		caret: /(^|[^\[])\^/g,
		percentDecode: /%25/g,
		findPipe: /\|/g,
		splitPipe: / \|/,
		slashPipe: /\\\|/g,
		carriageReturn: /\r\n|\r/g,
		spaceLine: /^ +$/gm,
		notSpaceStart: /^\S*/,
		endingNewline: /\n$/,
		listItemRegex: (u) => new RegExp(`^( {0,3}${u})((?:[	 ][^\\n]*)?(?:\\n|$))`),
		nextBulletRegex: (u) => new RegExp(`^ {0,${Math.min(3, u - 1)}}(?:[*+-]|\\d{1,9}[.)])((?:[ 	][^\\n]*)?(?:\\n|$))`),
		hrRegex: (u) => new RegExp(`^ {0,${Math.min(3, u - 1)}}((?:- *){3,}|(?:_ *){3,}|(?:\\* *){3,})(?:\\n+|$)`),
		fencesBeginRegex: (u) => new RegExp(`^ {0,${Math.min(3, u - 1)}}(?:\`\`\`|~~~)`),
		headingBeginRegex: (u) => new RegExp(`^ {0,${Math.min(3, u - 1)}}#`),
		htmlBeginRegex: (u) => new RegExp(`^ {0,${Math.min(3, u - 1)}}<(?:[a-z].*>|!--)`, "i"),
		blockquoteBeginRegex: (u) => new RegExp(`^ {0,${Math.min(3, u - 1)}}>`)
	}, Re = /^(?:[ \t]*(?:\n|$))+/, Te = /^((?: {4}| {0,3}\t)[^\n]+(?:\n(?:[ \t]*(?:\n|$))*)?)+/, Oe = /^ {0,3}(`{3,}(?=[^`\n]*(?:\n|$))|~{3,})([^\n]*)(?:\n|$)(?:|([\s\S]*?)(?:\n|$))(?: {0,3}\1[~`]* *(?=\n|$)|$)/, C = /^ {0,3}((?:-[\t ]*){3,}|(?:_[ \t]*){3,}|(?:\*[ \t]*){3,})(?:\n+|$)/, we = /^ {0,3}(#{1,6})(?=\s|$)(.*)(?:\n+|$)/, Q = / {0,3}(?:[*+-]|\d{1,9}[.)])/, se = /^(?!bull |blockCode|fences|blockquote|heading|html|table)((?:.|\n(?!\s*?\n|bull |blockCode|fences|blockquote|heading|html|table))+?)\n {0,3}(=+|-+) *(?:\n+|$)/, ie = k(se).replace(/bull/g, Q).replace(/blockCode/g, /(?: {4}| {0,3}\t)/).replace(/fences/g, / {0,3}(?:`{3,}|~{3,})/).replace(/blockquote/g, / {0,3}>/).replace(/heading/g, / {0,3}#{1,6}/).replace(/html/g, / {0,3}<[^\n>]+>\n/).replace(/\|table/g, "").getRegex(), ye = k(se).replace(/bull/g, Q).replace(/blockCode/g, /(?: {4}| {0,3}\t)/).replace(/fences/g, / {0,3}(?:`{3,}|~{3,})/).replace(/blockquote/g, / {0,3}>/).replace(/heading/g, / {0,3}#{1,6}/).replace(/html/g, / {0,3}<[^\n>]+>\n/).replace(/table/g, / {0,3}\|?(?:[:\- ]*\|)+[\:\- ]*\n/).getRegex(), j = /^([^\n]+(?:\n(?!hr|heading|lheading|blockquote|fences|list|html|table| +\n)[^\n]+)*)/, Pe = /^[^\n]+/, F = /(?!\s*\])(?:\\[\s\S]|[^\[\]\\])+/, Se = k(/^ {0,3}\[(label)\]: *(?:\n[ \t]*)?([^<\s][^\s]*|<.*?>)(?:(?: +(?:\n[ \t]*)?| *\n[ \t]*)(title))? *(?:\n+|$)/).replace("label", F).replace("title", /(?:"(?:\\"?|[^"\\])*"|'[^'\n]*(?:\n[^'\n]+)*\n?'|\([^()]*\))/).getRegex(), $e = k(/^(bull)([ \t][^\n]+?)?(?:\n|$)/).replace(/bull/g, Q).getRegex(), v = "address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h[1-6]|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|meta|nav|noframes|ol|optgroup|option|p|param|search|section|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul", U = /<!--(?:-?>|[\s\S]*?(?:-->|$))/, _e = k("^ {0,3}(?:<(script|pre|style|textarea)[\\s>][\\s\\S]*?(?:</\\1>[^\\n]*\\n+|$)|comment[^\\n]*(\\n+|$)|<\\?[\\s\\S]*?(?:\\?>\\n*|$)|<![A-Z][\\s\\S]*?(?:>\\n*|$)|<!\\[CDATA\\[[\\s\\S]*?(?:\\]\\]>\\n*|$)|</?(tag)(?: +|\\n|/?>)[\\s\\S]*?(?:(?:\\n[ 	]*)+\\n|$)|<(?!script|pre|style|textarea)([a-z][\\w-]*)(?:attribute)*? */?>(?=[ \\t]*(?:\\n|$))[\\s\\S]*?(?:(?:\\n[ 	]*)+\\n|$)|</(?!script|pre|style|textarea)[a-z][\\w-]*\\s*>(?=[ \\t]*(?:\\n|$))[\\s\\S]*?(?:(?:\\n[ 	]*)+\\n|$))", "i").replace("comment", U).replace("tag", v).replace("attribute", / +[a-zA-Z:_][\w.:-]*(?: *= *"[^"\n]*"| *= *'[^'\n]*'| *= *[^\s"'=<>`]+)?/).getRegex(), oe = k(j).replace("hr", C).replace("heading", " {0,3}#{1,6}(?:\\s|$)").replace("|lheading", "").replace("|table", "").replace("blockquote", " {0,3}>").replace("fences", " {0,3}(?:`{3,}(?=[^`\\n]*\\n)|~{3,})[^\\n]*\\n").replace("list", " {0,3}(?:[*+-]|1[.)])[ \\t]").replace("html", "</?(?:tag)(?: +|\\n|/?>)|<(?:script|pre|style|textarea|!--)").replace("tag", v).getRegex(), K = {
		blockquote: k(/^( {0,3}> ?(paragraph|[^\n]*)(?:\n|$))+/).replace("paragraph", oe).getRegex(),
		code: Te,
		def: Se,
		fences: Oe,
		heading: we,
		hr: C,
		html: _e,
		lheading: ie,
		list: $e,
		newline: Re,
		paragraph: oe,
		table: _,
		text: Pe
	}, ne = k("^ *([^\\n ].*)\\n {0,3}((?:\\| *)?:?-+:? *(?:\\| *:?-+:? *)*(?:\\| *)?)(?:\\n((?:(?! *\\n|hr|heading|blockquote|code|fences|list|html).*(?:\\n|$))*)\\n*|$)").replace("hr", C).replace("heading", " {0,3}#{1,6}(?:\\s|$)").replace("blockquote", " {0,3}>").replace("code", "(?: {4}| {0,3}	)[^\\n]").replace("fences", " {0,3}(?:`{3,}(?=[^`\\n]*\\n)|~{3,})[^\\n]*\\n").replace("list", " {0,3}(?:[*+-]|1[.)])[ \\t]").replace("html", "</?(?:tag)(?: +|\\n|/?>)|<(?:script|pre|style|textarea|!--)").replace("tag", v).getRegex(), Me = {
		...K,
		lheading: ye,
		table: ne,
		paragraph: k(j).replace("hr", C).replace("heading", " {0,3}#{1,6}(?:\\s|$)").replace("|lheading", "").replace("table", ne).replace("blockquote", " {0,3}>").replace("fences", " {0,3}(?:`{3,}(?=[^`\\n]*\\n)|~{3,})[^\\n]*\\n").replace("list", " {0,3}(?:[*+-]|1[.)])[ \\t]").replace("html", "</?(?:tag)(?: +|\\n|/?>)|<(?:script|pre|style|textarea|!--)").replace("tag", v).getRegex()
	}, ze = {
		...K,
		html: k(`^ *(?:comment *(?:\\n|\\s*$)|<(tag)[\\s\\S]+?</\\1> *(?:\\n{2,}|\\s*$)|<tag(?:"[^"]*"|'[^']*'|\\s[^'"/>\\s]*)*?/?> *(?:\\n{2,}|\\s*$))`).replace("comment", U).replace(/tag/g, "(?!(?:a|em|strong|small|s|cite|q|dfn|abbr|data|time|code|var|samp|kbd|sub|sup|i|b|u|mark|ruby|rt|rp|bdi|bdo|span|br|wbr|ins|del|img)\\b)\\w+(?!:|[^\\w\\s@]*@)\\b").getRegex(),
		def: /^ *\[([^\]]+)\]: *<?([^\s>]+)>?(?: +(["(][^\n]+[")]))? *(?:\n+|$)/,
		heading: /^(#{1,6})(.*)(?:\n+|$)/,
		fences: _,
		lheading: /^(.+?)\n {0,3}(=+|-+) *(?:\n+|$)/,
		paragraph: k(j).replace("hr", C).replace("heading", ` *#{1,6} *[^
]`).replace("lheading", ie).replace("|table", "").replace("blockquote", " {0,3}>").replace("|fences", "").replace("|list", "").replace("|html", "").replace("|tag", "").getRegex()
	}, Ee = /^\\([!"#$%&'()*+,\-./:;<=>?@\[\]\\^_`{|}~])/, Ie = /^(`+)([^`]|[^`][\s\S]*?[^`])\1(?!`)/, ae = /^( {2,}|\\)\n(?!\s*$)/, Ae = /^(`+|[^`])(?:(?= {2,}\n)|[\s\S]*?(?:(?=[\\<!\[`*_]|\b_|$)|[^ ](?= {2,}\n)))/, z = /[\p{P}\p{S}]/u, H = /[\s\p{P}\p{S}]/u, W = /[^\s\p{P}\p{S}]/u, Ce = k(/^((?![*_])punctSpace)/, "u").replace(/punctSpace/g, H).getRegex(), le = /(?!~)[\p{P}\p{S}]/u, Be = /(?!~)[\s\p{P}\p{S}]/u, De = /(?:[^\s\p{P}\p{S}]|~)/u, qe = k(/link|precode-code|html/, "g").replace("link", /\[(?:[^\[\]`]|(?<a>`+)[^`]+\k<a>(?!`))*?\]\((?:\\[\s\S]|[^\\\(\)]|\((?:\\[\s\S]|[^\\\(\)])*\))*\)/).replace("precode-", be ? "(?<!`)()" : "(^^|[^`])").replace("code", /(?<b>`+)[^`]+\k<b>(?!`)/).replace("html", /<(?! )[^<>]*?>/).getRegex(), ue = /^(?:\*+(?:((?!\*)punct)|([^\s*]))?)|^_+(?:((?!_)punct)|([^\s_]))?/, ve = k(ue, "u").replace(/punct/g, z).getRegex(), He = k(ue, "u").replace(/punct/g, le).getRegex(), pe = "^[^_*]*?__[^_*]*?\\*[^_*]*?(?=__)|[^*]+(?=[^*])|(?!\\*)punct(\\*+)(?=[\\s]|$)|notPunctSpace(\\*+)(?!\\*)(?=punctSpace|$)|(?!\\*)punctSpace(\\*+)(?=notPunctSpace)|[\\s](\\*+)(?!\\*)(?=punct)|(?!\\*)punct(\\*+)(?!\\*)(?=punct)|notPunctSpace(\\*+)(?=notPunctSpace)", Ze = k(pe, "gu").replace(/notPunctSpace/g, W).replace(/punctSpace/g, H).replace(/punct/g, z).getRegex(), Ge = k(pe, "gu").replace(/notPunctSpace/g, De).replace(/punctSpace/g, Be).replace(/punct/g, le).getRegex(), Ne = k("^[^_*]*?\\*\\*[^_*]*?_[^_*]*?(?=\\*\\*)|[^_]+(?=[^_])|(?!_)punct(_+)(?=[\\s]|$)|notPunctSpace(_+)(?!_)(?=punctSpace|$)|(?!_)punctSpace(_+)(?=notPunctSpace)|[\\s](_+)(?!_)(?=punct)|(?!_)punct(_+)(?!_)(?=punct)", "gu").replace(/notPunctSpace/g, W).replace(/punctSpace/g, H).replace(/punct/g, z).getRegex(), Qe = k(/^~~?(?:((?!~)punct)|[^\s~])/, "u").replace(/punct/g, z).getRegex(), Fe = k("^[^~]+(?=[^~])|(?!~)punct(~~?)(?=[\\s]|$)|notPunctSpace(~~?)(?!~)(?=punctSpace|$)|(?!~)punctSpace(~~?)(?=notPunctSpace)|[\\s](~~?)(?!~)(?=punct)|(?!~)punct(~~?)(?!~)(?=punct)|notPunctSpace(~~?)(?=notPunctSpace)", "gu").replace(/notPunctSpace/g, W).replace(/punctSpace/g, H).replace(/punct/g, z).getRegex(), Ue = k(/\\(punct)/, "gu").replace(/punct/g, z).getRegex(), Ke = k(/^<(scheme:[^\s\x00-\x1f<>]*|email)>/).replace("scheme", /[a-zA-Z][a-zA-Z0-9+.-]{1,31}/).replace("email", /[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+(@)[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+(?![-_])/).getRegex(), We = k(U).replace("(?:-->|$)", "-->").getRegex(), Xe = k("^comment|^</[a-zA-Z][\\w:-]*\\s*>|^<[a-zA-Z][\\w-]*(?:attribute)*?\\s*/?>|^<\\?[\\s\\S]*?\\?>|^<![a-zA-Z]+\\s[\\s\\S]*?>|^<!\\[CDATA\\[[\\s\\S]*?\\]\\]>").replace("comment", We).replace("attribute", /\s+[a-zA-Z:_][\w.:-]*(?:\s*=\s*"[^"]*"|\s*=\s*'[^']*'|\s*=\s*[^\s"'=<>`]+)?/).getRegex(), q = /(?:\[(?:\\[\s\S]|[^\[\]\\])*\]|\\[\s\S]|`+(?!`)[^`]*?`+(?!`)|``+(?=\])|[^\[\]\\`])*?/, Je = k(/^!?\[(label)\]\(\s*(href)(?:(?:[ \t]+(?:\n[ \t]*)?|\n[ \t]*)(title))?\s*\)/).replace("label", q).replace("href", /<(?:\\.|[^\n<>\\])+>|[^ \t\n\x00-\x1f]*/).replace("title", /"(?:\\"?|[^"\\])*"|'(?:\\'?|[^'\\])*'|\((?:\\\)?|[^)\\])*\)/).getRegex(), ce = k(/^!?\[(label)\]\[(ref)\]/).replace("label", q).replace("ref", F).getRegex(), he = k(/^!?\[(ref)\](?:\[\])?/).replace("ref", F).getRegex(), Ve = k("reflink|nolink(?!\\()", "g").replace("reflink", ce).replace("nolink", he).getRegex(), re = /[hH][tT][tT][pP][sS]?|[fF][tT][pP]/, X = {
		_backpedal: _,
		anyPunctuation: Ue,
		autolink: Ke,
		blockSkip: qe,
		br: ae,
		code: Ie,
		del: _,
		delLDelim: _,
		delRDelim: _,
		emStrongLDelim: ve,
		emStrongRDelimAst: Ze,
		emStrongRDelimUnd: Ne,
		escape: Ee,
		link: Je,
		nolink: he,
		punctuation: Ce,
		reflink: ce,
		reflinkSearch: Ve,
		tag: Xe,
		text: Ae,
		url: _
	}, Ye = {
		...X,
		link: k(/^!?\[(label)\]\((.*?)\)/).replace("label", q).getRegex(),
		reflink: k(/^!?\[(label)\]\s*\[([^\]]*)\]/).replace("label", q).getRegex()
	}, N = {
		...X,
		emStrongRDelimAst: Ge,
		emStrongLDelim: He,
		delLDelim: Qe,
		delRDelim: Fe,
		url: k(/^((?:protocol):\/\/|www\.)(?:[a-zA-Z0-9\-]+\.?)+[^\s<]*|^email/).replace("protocol", re).replace("email", /[A-Za-z0-9._+-]+(@)[a-zA-Z0-9-_]+(?:\.[a-zA-Z0-9-_]*[a-zA-Z0-9])+(?![-_])/).getRegex(),
		_backpedal: /(?:[^?!.,:;*_'"~()&]+|\([^)]*\)|&(?![a-zA-Z0-9]+;$)|[?!.,:;*_'"~)]+(?!$))+/,
		del: /^(~~?)(?=[^\s~])((?:\\[\s\S]|[^\\])*?(?:\\[\s\S]|[^\s~\\]))\1(?=[^~]|$)/,
		text: k(/^([`~]+|[^`~])(?:(?= {2,}\n)|(?=[a-zA-Z0-9.!#$%&'*+\/=?_`{\|}~-]+@)|[\s\S]*?(?:(?=[\\<!\[`*~_]|\b_|protocol:\/\/|www\.|$)|[^ ](?= {2,}\n)|[^a-zA-Z0-9.!#$%&'*+\/=?_`{\|}~-](?=[a-zA-Z0-9.!#$%&'*+\/=?_`{\|}~-]+@)))/).replace("protocol", re).getRegex()
	}, et = {
		...N,
		br: k(ae).replace("{2,}", "*").getRegex(),
		text: k(N.text).replace("\\b_", "\\b_| {2,}\\n").replace(/\{2,\}/g, "*").getRegex()
	}, B = {
		normal: K,
		gfm: Me,
		pedantic: ze
	}, E = {
		normal: X,
		gfm: N,
		breaks: et,
		pedantic: Ye
	};
	var tt = {
		"&": "&amp;",
		"<": "&lt;",
		">": "&gt;",
		"\"": "&quot;",
		"'": "&#39;"
	}, ke = (u) => tt[u];
	function O(u, e) {
		if (e) {
			if (m.escapeTest.test(u)) return u.replace(m.escapeReplace, ke);
		} else if (m.escapeTestNoEncode.test(u)) return u.replace(m.escapeReplaceNoEncode, ke);
		return u;
	}
	function J(u) {
		try {
			u = encodeURI(u).replace(m.percentDecode, "%");
		} catch {
			return null;
		}
		return u;
	}
	function V(u, e) {
		let n = u.replace(m.findPipe, (i, s, a) => {
			let o = !1, l = s;
			for (; --l >= 0 && a[l] === "\\";) o = !o;
			return o ? "|" : " |";
		}).split(m.splitPipe), r = 0;
		if (n[0].trim() || n.shift(), n.length > 0 && !n.at(-1)?.trim() && n.pop(), e) if (n.length > e) n.splice(e);
		else for (; n.length < e;) n.push("");
		for (; r < n.length; r++) n[r] = n[r].trim().replace(m.slashPipe, "|");
		return n;
	}
	function I(u, e, t) {
		let n = u.length;
		if (n === 0) return "";
		let r = 0;
		for (; r < n;) {
			let i = u.charAt(n - r - 1);
			if (i === e && !t) r++;
			else if (i !== e && t) r++;
			else break;
		}
		return u.slice(0, n - r);
	}
	function de(u, e) {
		if (u.indexOf(e[1]) === -1) return -1;
		let t = 0;
		for (let n = 0; n < u.length; n++) if (u[n] === "\\") n++;
		else if (u[n] === e[0]) t++;
		else if (u[n] === e[1] && (t--, t < 0)) return n;
		return t > 0 ? -2 : -1;
	}
	function ge(u, e = 0) {
		let t = e, n = "";
		for (let r of u) if (r === "	") {
			let i = 4 - t % 4;
			n += " ".repeat(i), t += i;
		} else n += r, t++;
		return n;
	}
	function fe(u, e, t, n, r) {
		let i = e.href, s = e.title || null, a = u[1].replace(r.other.outputLinkReplace, "$1");
		n.state.inLink = !0;
		let o = {
			type: u[0].charAt(0) === "!" ? "image" : "link",
			raw: t,
			href: i,
			title: s,
			text: a,
			tokens: n.inlineTokens(a)
		};
		return n.state.inLink = !1, o;
	}
	function nt(u, e, t) {
		let n = u.match(t.other.indentCodeCompensation);
		if (n === null) return e;
		let r = n[1];
		return e.split(`
`).map((i) => {
			let s = i.match(t.other.beginningSpace);
			if (s === null) return i;
			let [a] = s;
			return a.length >= r.length ? i.slice(r.length) : i;
		}).join(`
`);
	}
	var w = class {
		options;
		rules;
		lexer;
		constructor(e) {
			this.options = e || T;
		}
		space(e) {
			let t = this.rules.block.newline.exec(e);
			if (t && t[0].length > 0) return {
				type: "space",
				raw: t[0]
			};
		}
		code(e) {
			let t = this.rules.block.code.exec(e);
			if (t) {
				let n = t[0].replace(this.rules.other.codeRemoveIndent, "");
				return {
					type: "code",
					raw: t[0],
					codeBlockStyle: "indented",
					text: this.options.pedantic ? n : I(n, `
`)
				};
			}
		}
		fences(e) {
			let t = this.rules.block.fences.exec(e);
			if (t) {
				let n = t[0], r = nt(n, t[3] || "", this.rules);
				return {
					type: "code",
					raw: n,
					lang: t[2] ? t[2].trim().replace(this.rules.inline.anyPunctuation, "$1") : t[2],
					text: r
				};
			}
		}
		heading(e) {
			let t = this.rules.block.heading.exec(e);
			if (t) {
				let n = t[2].trim();
				if (this.rules.other.endingHash.test(n)) {
					let r = I(n, "#");
					(this.options.pedantic || !r || this.rules.other.endingSpaceChar.test(r)) && (n = r.trim());
				}
				return {
					type: "heading",
					raw: t[0],
					depth: t[1].length,
					text: n,
					tokens: this.lexer.inline(n)
				};
			}
		}
		hr(e) {
			let t = this.rules.block.hr.exec(e);
			if (t) return {
				type: "hr",
				raw: I(t[0], `
`)
			};
		}
		blockquote(e) {
			let t = this.rules.block.blockquote.exec(e);
			if (t) {
				let n = I(t[0], `
`).split(`
`), r = "", i = "", s = [];
				for (; n.length > 0;) {
					let a = !1, o = [], l;
					for (l = 0; l < n.length; l++) if (this.rules.other.blockquoteStart.test(n[l])) o.push(n[l]), a = !0;
					else if (!a) o.push(n[l]);
					else break;
					n = n.slice(l);
					let p = o.join(`
`), c = p.replace(this.rules.other.blockquoteSetextReplace, `
    $1`).replace(this.rules.other.blockquoteSetextReplace2, "");
					r = r ? `${r}
${p}` : p, i = i ? `${i}
${c}` : c;
					let d = this.lexer.state.top;
					if (this.lexer.state.top = !0, this.lexer.blockTokens(c, s, !0), this.lexer.state.top = d, n.length === 0) break;
					let h = s.at(-1);
					if (h?.type === "code") break;
					if (h?.type === "blockquote") {
						let R = h, f = R.raw + `
` + n.join(`
`), S = this.blockquote(f);
						s[s.length - 1] = S, r = r.substring(0, r.length - R.raw.length) + S.raw, i = i.substring(0, i.length - R.text.length) + S.text;
						break;
					} else if (h?.type === "list") {
						let R = h, f = R.raw + `
` + n.join(`
`), S = this.list(f);
						s[s.length - 1] = S, r = r.substring(0, r.length - h.raw.length) + S.raw, i = i.substring(0, i.length - R.raw.length) + S.raw, n = f.substring(s.at(-1).raw.length).split(`
`);
						continue;
					}
				}
				return {
					type: "blockquote",
					raw: r,
					tokens: s,
					text: i
				};
			}
		}
		list(e) {
			let t = this.rules.block.list.exec(e);
			if (t) {
				let n = t[1].trim(), r = n.length > 1, i = {
					type: "list",
					raw: "",
					ordered: r,
					start: r ? +n.slice(0, -1) : "",
					loose: !1,
					items: []
				};
				n = r ? `\\d{1,9}\\${n.slice(-1)}` : `\\${n}`, this.options.pedantic && (n = r ? n : "[*+-]");
				let s = this.rules.other.listItemRegex(n), a = !1;
				for (; e;) {
					let l = !1, p = "", c = "";
					if (!(t = s.exec(e)) || this.rules.block.hr.test(e)) break;
					p = t[0], e = e.substring(p.length);
					let d = ge(t[2].split(`
`, 1)[0], t[1].length), h = e.split(`
`, 1)[0], R = !d.trim(), f = 0;
					if (this.options.pedantic ? (f = 2, c = d.trimStart()) : R ? f = t[1].length + 1 : (f = d.search(this.rules.other.nonSpaceChar), f = f > 4 ? 1 : f, c = d.slice(f), f += t[1].length), R && this.rules.other.blankLine.test(h) && (p += h + `
`, e = e.substring(h.length + 1), l = !0), !l) {
						let S = this.rules.other.nextBulletRegex(f), Y = this.rules.other.hrRegex(f), ee = this.rules.other.fencesBeginRegex(f), te = this.rules.other.headingBeginRegex(f), me = this.rules.other.htmlBeginRegex(f), xe = this.rules.other.blockquoteBeginRegex(f);
						for (; e;) {
							let Z = e.split(`
`, 1)[0], A;
							if (h = Z, this.options.pedantic ? (h = h.replace(this.rules.other.listReplaceNesting, "  "), A = h) : A = h.replace(this.rules.other.tabCharGlobal, "    "), ee.test(h) || te.test(h) || me.test(h) || xe.test(h) || S.test(h) || Y.test(h)) break;
							if (A.search(this.rules.other.nonSpaceChar) >= f || !h.trim()) c += `
` + A.slice(f);
							else {
								if (R || d.replace(this.rules.other.tabCharGlobal, "    ").search(this.rules.other.nonSpaceChar) >= 4 || ee.test(d) || te.test(d) || Y.test(d)) break;
								c += `
` + h;
							}
							R = !h.trim(), p += Z + `
`, e = e.substring(Z.length + 1), d = A.slice(f);
						}
					}
					i.loose || (a ? i.loose = !0 : this.rules.other.doubleBlankLine.test(p) && (a = !0)), i.items.push({
						type: "list_item",
						raw: p,
						task: !!this.options.gfm && this.rules.other.listIsTask.test(c),
						loose: !1,
						text: c,
						tokens: []
					}), i.raw += p;
				}
				let o = i.items.at(-1);
				if (o) o.raw = o.raw.trimEnd(), o.text = o.text.trimEnd();
				else return;
				i.raw = i.raw.trimEnd();
				for (let l of i.items) {
					if (this.lexer.state.top = !1, l.tokens = this.lexer.blockTokens(l.text, []), l.task) {
						if (l.text = l.text.replace(this.rules.other.listReplaceTask, ""), l.tokens[0]?.type === "text" || l.tokens[0]?.type === "paragraph") {
							l.tokens[0].raw = l.tokens[0].raw.replace(this.rules.other.listReplaceTask, ""), l.tokens[0].text = l.tokens[0].text.replace(this.rules.other.listReplaceTask, "");
							for (let c = this.lexer.inlineQueue.length - 1; c >= 0; c--) if (this.rules.other.listIsTask.test(this.lexer.inlineQueue[c].src)) {
								this.lexer.inlineQueue[c].src = this.lexer.inlineQueue[c].src.replace(this.rules.other.listReplaceTask, "");
								break;
							}
						}
						let p = this.rules.other.listTaskCheckbox.exec(l.raw);
						if (p) {
							let c = {
								type: "checkbox",
								raw: p[0] + " ",
								checked: p[0] !== "[ ]"
							};
							l.checked = c.checked, i.loose ? l.tokens[0] && ["paragraph", "text"].includes(l.tokens[0].type) && "tokens" in l.tokens[0] && l.tokens[0].tokens ? (l.tokens[0].raw = c.raw + l.tokens[0].raw, l.tokens[0].text = c.raw + l.tokens[0].text, l.tokens[0].tokens.unshift(c)) : l.tokens.unshift({
								type: "paragraph",
								raw: c.raw,
								text: c.raw,
								tokens: [c]
							}) : l.tokens.unshift(c);
						}
					}
					if (!i.loose) {
						let p = l.tokens.filter((d) => d.type === "space");
						i.loose = p.length > 0 && p.some((d) => this.rules.other.anyLine.test(d.raw));
					}
				}
				if (i.loose) for (let l of i.items) {
					l.loose = !0;
					for (let p of l.tokens) p.type === "text" && (p.type = "paragraph");
				}
				return i;
			}
		}
		html(e) {
			let t = this.rules.block.html.exec(e);
			if (t) return {
				type: "html",
				block: !0,
				raw: t[0],
				pre: t[1] === "pre" || t[1] === "script" || t[1] === "style",
				text: t[0]
			};
		}
		def(e) {
			let t = this.rules.block.def.exec(e);
			if (t) {
				let n = t[1].toLowerCase().replace(this.rules.other.multipleSpaceGlobal, " "), r = t[2] ? t[2].replace(this.rules.other.hrefBrackets, "$1").replace(this.rules.inline.anyPunctuation, "$1") : "", i = t[3] ? t[3].substring(1, t[3].length - 1).replace(this.rules.inline.anyPunctuation, "$1") : t[3];
				return {
					type: "def",
					tag: n,
					raw: t[0],
					href: r,
					title: i
				};
			}
		}
		table(e) {
			let t = this.rules.block.table.exec(e);
			if (!t || !this.rules.other.tableDelimiter.test(t[2])) return;
			let n = V(t[1]), r = t[2].replace(this.rules.other.tableAlignChars, "").split("|"), i = t[3]?.trim() ? t[3].replace(this.rules.other.tableRowBlankLine, "").split(`
`) : [], s = {
				type: "table",
				raw: t[0],
				header: [],
				align: [],
				rows: []
			};
			if (n.length === r.length) {
				for (let a of r) this.rules.other.tableAlignRight.test(a) ? s.align.push("right") : this.rules.other.tableAlignCenter.test(a) ? s.align.push("center") : this.rules.other.tableAlignLeft.test(a) ? s.align.push("left") : s.align.push(null);
				for (let a = 0; a < n.length; a++) s.header.push({
					text: n[a],
					tokens: this.lexer.inline(n[a]),
					header: !0,
					align: s.align[a]
				});
				for (let a of i) s.rows.push(V(a, s.header.length).map((o, l) => ({
					text: o,
					tokens: this.lexer.inline(o),
					header: !1,
					align: s.align[l]
				})));
				return s;
			}
		}
		lheading(e) {
			let t = this.rules.block.lheading.exec(e);
			if (t) {
				let n = t[1].trim();
				return {
					type: "heading",
					raw: t[0],
					depth: t[2].charAt(0) === "=" ? 1 : 2,
					text: n,
					tokens: this.lexer.inline(n)
				};
			}
		}
		paragraph(e) {
			let t = this.rules.block.paragraph.exec(e);
			if (t) {
				let n = t[1].charAt(t[1].length - 1) === `
` ? t[1].slice(0, -1) : t[1];
				return {
					type: "paragraph",
					raw: t[0],
					text: n,
					tokens: this.lexer.inline(n)
				};
			}
		}
		text(e) {
			let t = this.rules.block.text.exec(e);
			if (t) return {
				type: "text",
				raw: t[0],
				text: t[0],
				tokens: this.lexer.inline(t[0])
			};
		}
		escape(e) {
			let t = this.rules.inline.escape.exec(e);
			if (t) return {
				type: "escape",
				raw: t[0],
				text: t[1]
			};
		}
		tag(e) {
			let t = this.rules.inline.tag.exec(e);
			if (t) return !this.lexer.state.inLink && this.rules.other.startATag.test(t[0]) ? this.lexer.state.inLink = !0 : this.lexer.state.inLink && this.rules.other.endATag.test(t[0]) && (this.lexer.state.inLink = !1), !this.lexer.state.inRawBlock && this.rules.other.startPreScriptTag.test(t[0]) ? this.lexer.state.inRawBlock = !0 : this.lexer.state.inRawBlock && this.rules.other.endPreScriptTag.test(t[0]) && (this.lexer.state.inRawBlock = !1), {
				type: "html",
				raw: t[0],
				inLink: this.lexer.state.inLink,
				inRawBlock: this.lexer.state.inRawBlock,
				block: !1,
				text: t[0]
			};
		}
		link(e) {
			let t = this.rules.inline.link.exec(e);
			if (t) {
				let n = t[2].trim();
				if (!this.options.pedantic && this.rules.other.startAngleBracket.test(n)) {
					if (!this.rules.other.endAngleBracket.test(n)) return;
					let s = I(n.slice(0, -1), "\\");
					if ((n.length - s.length) % 2 === 0) return;
				} else {
					let s = de(t[2], "()");
					if (s === -2) return;
					if (s > -1) {
						let o = (t[0].indexOf("!") === 0 ? 5 : 4) + t[1].length + s;
						t[2] = t[2].substring(0, s), t[0] = t[0].substring(0, o).trim(), t[3] = "";
					}
				}
				let r = t[2], i = "";
				if (this.options.pedantic) {
					let s = this.rules.other.pedanticHrefTitle.exec(r);
					s && (r = s[1], i = s[3]);
				} else i = t[3] ? t[3].slice(1, -1) : "";
				return r = r.trim(), this.rules.other.startAngleBracket.test(r) && (this.options.pedantic && !this.rules.other.endAngleBracket.test(n) ? r = r.slice(1) : r = r.slice(1, -1)), fe(t, {
					href: r && r.replace(this.rules.inline.anyPunctuation, "$1"),
					title: i && i.replace(this.rules.inline.anyPunctuation, "$1")
				}, t[0], this.lexer, this.rules);
			}
		}
		reflink(e, t) {
			let n;
			if ((n = this.rules.inline.reflink.exec(e)) || (n = this.rules.inline.nolink.exec(e))) {
				let i = t[(n[2] || n[1]).replace(this.rules.other.multipleSpaceGlobal, " ").toLowerCase()];
				if (!i) {
					let s = n[0].charAt(0);
					return {
						type: "text",
						raw: s,
						text: s
					};
				}
				return fe(n, i, n[0], this.lexer, this.rules);
			}
		}
		emStrong(e, t, n = "") {
			let r = this.rules.inline.emStrongLDelim.exec(e);
			if (!r || !r[1] && !r[2] && !r[3] && !r[4] || r[4] && n.match(this.rules.other.unicodeAlphaNumeric)) return;
			if (!(r[1] || r[3] || "") || !n || this.rules.inline.punctuation.exec(n)) {
				let s = [...r[0]].length - 1, a, o, l = s, p = 0, c = r[0][0] === "*" ? this.rules.inline.emStrongRDelimAst : this.rules.inline.emStrongRDelimUnd;
				for (c.lastIndex = 0, t = t.slice(-1 * e.length + s); (r = c.exec(t)) != null;) {
					if (a = r[1] || r[2] || r[3] || r[4] || r[5] || r[6], !a) continue;
					if (o = [...a].length, r[3] || r[4]) {
						l += o;
						continue;
					} else if ((r[5] || r[6]) && s % 3 && !((s + o) % 3)) {
						p += o;
						continue;
					}
					if (l -= o, l > 0) continue;
					o = Math.min(o, o + l + p);
					let d = [...r[0]][0].length, h = e.slice(0, s + r.index + d + o);
					if (Math.min(s, o) % 2) {
						let f = h.slice(1, -1);
						return {
							type: "em",
							raw: h,
							text: f,
							tokens: this.lexer.inlineTokens(f)
						};
					}
					let R = h.slice(2, -2);
					return {
						type: "strong",
						raw: h,
						text: R,
						tokens: this.lexer.inlineTokens(R)
					};
				}
			}
		}
		codespan(e) {
			let t = this.rules.inline.code.exec(e);
			if (t) {
				let n = t[2].replace(this.rules.other.newLineCharGlobal, " "), r = this.rules.other.nonSpaceChar.test(n), i = this.rules.other.startingSpaceChar.test(n) && this.rules.other.endingSpaceChar.test(n);
				return r && i && (n = n.substring(1, n.length - 1)), {
					type: "codespan",
					raw: t[0],
					text: n
				};
			}
		}
		br(e) {
			let t = this.rules.inline.br.exec(e);
			if (t) return {
				type: "br",
				raw: t[0]
			};
		}
		del(e, t, n = "") {
			let r = this.rules.inline.delLDelim.exec(e);
			if (!r) return;
			if (!(r[1] || "") || !n || this.rules.inline.punctuation.exec(n)) {
				let s = [...r[0]].length - 1, a, o, l = s, p = this.rules.inline.delRDelim;
				for (p.lastIndex = 0, t = t.slice(-1 * e.length + s); (r = p.exec(t)) != null;) {
					if (a = r[1] || r[2] || r[3] || r[4] || r[5] || r[6], !a || (o = [...a].length, o !== s)) continue;
					if (r[3] || r[4]) {
						l += o;
						continue;
					}
					if (l -= o, l > 0) continue;
					o = Math.min(o, o + l);
					let c = [...r[0]][0].length, d = e.slice(0, s + r.index + c + o), h = d.slice(s, -s);
					return {
						type: "del",
						raw: d,
						text: h,
						tokens: this.lexer.inlineTokens(h)
					};
				}
			}
		}
		autolink(e) {
			let t = this.rules.inline.autolink.exec(e);
			if (t) {
				let n, r;
				return t[2] === "@" ? (n = t[1], r = "mailto:" + n) : (n = t[1], r = n), {
					type: "link",
					raw: t[0],
					text: n,
					href: r,
					tokens: [{
						type: "text",
						raw: n,
						text: n
					}]
				};
			}
		}
		url(e) {
			let t;
			if (t = this.rules.inline.url.exec(e)) {
				let n, r;
				if (t[2] === "@") n = t[0], r = "mailto:" + n;
				else {
					let i;
					do
						i = t[0], t[0] = this.rules.inline._backpedal.exec(t[0])?.[0] ?? "";
					while (i !== t[0]);
					n = t[0], t[1] === "www." ? r = "http://" + t[0] : r = t[0];
				}
				return {
					type: "link",
					raw: t[0],
					text: n,
					href: r,
					tokens: [{
						type: "text",
						raw: n,
						text: n
					}]
				};
			}
		}
		inlineText(e) {
			let t = this.rules.inline.text.exec(e);
			if (t) {
				let n = this.lexer.state.inRawBlock;
				return {
					type: "text",
					raw: t[0],
					text: t[0],
					escaped: n
				};
			}
		}
	};
	var x = class u {
		tokens;
		options;
		state;
		inlineQueue;
		tokenizer;
		constructor(e) {
			this.tokens = [], this.tokens.links = Object.create(null), this.options = e || T, this.options.tokenizer = this.options.tokenizer || new w(), this.tokenizer = this.options.tokenizer, this.tokenizer.options = this.options, this.tokenizer.lexer = this, this.inlineQueue = [], this.state = {
				inLink: !1,
				inRawBlock: !1,
				top: !0
			};
			let t = {
				other: m,
				block: B.normal,
				inline: E.normal
			};
			this.options.pedantic ? (t.block = B.pedantic, t.inline = E.pedantic) : this.options.gfm && (t.block = B.gfm, this.options.breaks ? t.inline = E.breaks : t.inline = E.gfm), this.tokenizer.rules = t;
		}
		static get rules() {
			return {
				block: B,
				inline: E
			};
		}
		static lex(e, t) {
			return new u(t).lex(e);
		}
		static lexInline(e, t) {
			return new u(t).inlineTokens(e);
		}
		lex(e) {
			e = e.replace(m.carriageReturn, `
`), this.blockTokens(e, this.tokens);
			for (let t = 0; t < this.inlineQueue.length; t++) {
				let n = this.inlineQueue[t];
				this.inlineTokens(n.src, n.tokens);
			}
			return this.inlineQueue = [], this.tokens;
		}
		blockTokens(e, t = [], n = !1) {
			for (this.tokenizer.lexer = this, this.options.pedantic && (e = e.replace(m.tabCharGlobal, "    ").replace(m.spaceLine, "")); e;) {
				let r;
				if (this.options.extensions?.block?.some((s) => (r = s.call({ lexer: this }, e, t)) ? (e = e.substring(r.raw.length), t.push(r), !0) : !1)) continue;
				if (r = this.tokenizer.space(e)) {
					e = e.substring(r.raw.length);
					let s = t.at(-1);
					r.raw.length === 1 && s !== void 0 ? s.raw += `
` : t.push(r);
					continue;
				}
				if (r = this.tokenizer.code(e)) {
					e = e.substring(r.raw.length);
					let s = t.at(-1);
					s?.type === "paragraph" || s?.type === "text" ? (s.raw += (s.raw.endsWith(`
`) ? "" : `
`) + r.raw, s.text += `
` + r.text, this.inlineQueue.at(-1).src = s.text) : t.push(r);
					continue;
				}
				if (r = this.tokenizer.fences(e)) {
					e = e.substring(r.raw.length), t.push(r);
					continue;
				}
				if (r = this.tokenizer.heading(e)) {
					e = e.substring(r.raw.length), t.push(r);
					continue;
				}
				if (r = this.tokenizer.hr(e)) {
					e = e.substring(r.raw.length), t.push(r);
					continue;
				}
				if (r = this.tokenizer.blockquote(e)) {
					e = e.substring(r.raw.length), t.push(r);
					continue;
				}
				if (r = this.tokenizer.list(e)) {
					e = e.substring(r.raw.length), t.push(r);
					continue;
				}
				if (r = this.tokenizer.html(e)) {
					e = e.substring(r.raw.length), t.push(r);
					continue;
				}
				if (r = this.tokenizer.def(e)) {
					e = e.substring(r.raw.length);
					let s = t.at(-1);
					s?.type === "paragraph" || s?.type === "text" ? (s.raw += (s.raw.endsWith(`
`) ? "" : `
`) + r.raw, s.text += `
` + r.raw, this.inlineQueue.at(-1).src = s.text) : this.tokens.links[r.tag] || (this.tokens.links[r.tag] = {
						href: r.href,
						title: r.title
					}, t.push(r));
					continue;
				}
				if (r = this.tokenizer.table(e)) {
					e = e.substring(r.raw.length), t.push(r);
					continue;
				}
				if (r = this.tokenizer.lheading(e)) {
					e = e.substring(r.raw.length), t.push(r);
					continue;
				}
				let i = e;
				if (this.options.extensions?.startBlock) {
					let s = Infinity, a = e.slice(1), o;
					this.options.extensions.startBlock.forEach((l) => {
						o = l.call({ lexer: this }, a), typeof o == "number" && o >= 0 && (s = Math.min(s, o));
					}), s < Infinity && s >= 0 && (i = e.substring(0, s + 1));
				}
				if (this.state.top && (r = this.tokenizer.paragraph(i))) {
					let s = t.at(-1);
					n && s?.type === "paragraph" ? (s.raw += (s.raw.endsWith(`
`) ? "" : `
`) + r.raw, s.text += `
` + r.text, this.inlineQueue.pop(), this.inlineQueue.at(-1).src = s.text) : t.push(r), n = i.length !== e.length, e = e.substring(r.raw.length);
					continue;
				}
				if (r = this.tokenizer.text(e)) {
					e = e.substring(r.raw.length);
					let s = t.at(-1);
					s?.type === "text" ? (s.raw += (s.raw.endsWith(`
`) ? "" : `
`) + r.raw, s.text += `
` + r.text, this.inlineQueue.pop(), this.inlineQueue.at(-1).src = s.text) : t.push(r);
					continue;
				}
				if (e) {
					let s = "Infinite loop on byte: " + e.charCodeAt(0);
					if (this.options.silent) {
						console.error(s);
						break;
					} else throw new Error(s);
				}
			}
			return this.state.top = !0, t;
		}
		inline(e, t = []) {
			return this.inlineQueue.push({
				src: e,
				tokens: t
			}), t;
		}
		inlineTokens(e, t = []) {
			this.tokenizer.lexer = this;
			let n = e, r = null;
			if (this.tokens.links) {
				let o = Object.keys(this.tokens.links);
				if (o.length > 0) for (; (r = this.tokenizer.rules.inline.reflinkSearch.exec(n)) != null;) o.includes(r[0].slice(r[0].lastIndexOf("[") + 1, -1)) && (n = n.slice(0, r.index) + "[" + "a".repeat(r[0].length - 2) + "]" + n.slice(this.tokenizer.rules.inline.reflinkSearch.lastIndex));
			}
			for (; (r = this.tokenizer.rules.inline.anyPunctuation.exec(n)) != null;) n = n.slice(0, r.index) + "++" + n.slice(this.tokenizer.rules.inline.anyPunctuation.lastIndex);
			let i;
			for (; (r = this.tokenizer.rules.inline.blockSkip.exec(n)) != null;) i = r[2] ? r[2].length : 0, n = n.slice(0, r.index + i) + "[" + "a".repeat(r[0].length - i - 2) + "]" + n.slice(this.tokenizer.rules.inline.blockSkip.lastIndex);
			n = this.options.hooks?.emStrongMask?.call({ lexer: this }, n) ?? n;
			let s = !1, a = "";
			for (; e;) {
				s || (a = ""), s = !1;
				let o;
				if (this.options.extensions?.inline?.some((p) => (o = p.call({ lexer: this }, e, t)) ? (e = e.substring(o.raw.length), t.push(o), !0) : !1)) continue;
				if (o = this.tokenizer.escape(e)) {
					e = e.substring(o.raw.length), t.push(o);
					continue;
				}
				if (o = this.tokenizer.tag(e)) {
					e = e.substring(o.raw.length), t.push(o);
					continue;
				}
				if (o = this.tokenizer.link(e)) {
					e = e.substring(o.raw.length), t.push(o);
					continue;
				}
				if (o = this.tokenizer.reflink(e, this.tokens.links)) {
					e = e.substring(o.raw.length);
					let p = t.at(-1);
					o.type === "text" && p?.type === "text" ? (p.raw += o.raw, p.text += o.text) : t.push(o);
					continue;
				}
				if (o = this.tokenizer.emStrong(e, n, a)) {
					e = e.substring(o.raw.length), t.push(o);
					continue;
				}
				if (o = this.tokenizer.codespan(e)) {
					e = e.substring(o.raw.length), t.push(o);
					continue;
				}
				if (o = this.tokenizer.br(e)) {
					e = e.substring(o.raw.length), t.push(o);
					continue;
				}
				if (o = this.tokenizer.del(e, n, a)) {
					e = e.substring(o.raw.length), t.push(o);
					continue;
				}
				if (o = this.tokenizer.autolink(e)) {
					e = e.substring(o.raw.length), t.push(o);
					continue;
				}
				if (!this.state.inLink && (o = this.tokenizer.url(e))) {
					e = e.substring(o.raw.length), t.push(o);
					continue;
				}
				let l = e;
				if (this.options.extensions?.startInline) {
					let p = Infinity, c = e.slice(1), d;
					this.options.extensions.startInline.forEach((h) => {
						d = h.call({ lexer: this }, c), typeof d == "number" && d >= 0 && (p = Math.min(p, d));
					}), p < Infinity && p >= 0 && (l = e.substring(0, p + 1));
				}
				if (o = this.tokenizer.inlineText(l)) {
					e = e.substring(o.raw.length), o.raw.slice(-1) !== "_" && (a = o.raw.slice(-1)), s = !0;
					let p = t.at(-1);
					p?.type === "text" ? (p.raw += o.raw, p.text += o.text) : t.push(o);
					continue;
				}
				if (e) {
					let p = "Infinite loop on byte: " + e.charCodeAt(0);
					if (this.options.silent) {
						console.error(p);
						break;
					} else throw new Error(p);
				}
			}
			return t;
		}
	};
	var y = class {
		options;
		parser;
		constructor(e) {
			this.options = e || T;
		}
		space(e) {
			return "";
		}
		code({ text: e, lang: t, escaped: n }) {
			let r = (t || "").match(m.notSpaceStart)?.[0], i = e.replace(m.endingNewline, "") + `
`;
			return r ? "<pre><code class=\"language-" + O(r) + "\">" + (n ? i : O(i, !0)) + `</code></pre>
` : "<pre><code>" + (n ? i : O(i, !0)) + `</code></pre>
`;
		}
		blockquote({ tokens: e }) {
			return `<blockquote>
${this.parser.parse(e)}</blockquote>
`;
		}
		html({ text: e }) {
			return e;
		}
		def(e) {
			return "";
		}
		heading({ tokens: e, depth: t }) {
			return `<h${t}>${this.parser.parseInline(e)}</h${t}>
`;
		}
		hr(e) {
			return `<hr>
`;
		}
		list(e) {
			let t = e.ordered, n = e.start, r = "";
			for (let a = 0; a < e.items.length; a++) {
				let o = e.items[a];
				r += this.listitem(o);
			}
			let i = t ? "ol" : "ul", s = t && n !== 1 ? " start=\"" + n + "\"" : "";
			return "<" + i + s + `>
` + r + "</" + i + `>
`;
		}
		listitem(e) {
			return `<li>${this.parser.parse(e.tokens)}</li>
`;
		}
		checkbox({ checked: e }) {
			return "<input " + (e ? "checked=\"\" " : "") + "disabled=\"\" type=\"checkbox\"> ";
		}
		paragraph({ tokens: e }) {
			return `<p>${this.parser.parseInline(e)}</p>
`;
		}
		table(e) {
			let t = "", n = "";
			for (let i = 0; i < e.header.length; i++) n += this.tablecell(e.header[i]);
			t += this.tablerow({ text: n });
			let r = "";
			for (let i = 0; i < e.rows.length; i++) {
				let s = e.rows[i];
				n = "";
				for (let a = 0; a < s.length; a++) n += this.tablecell(s[a]);
				r += this.tablerow({ text: n });
			}
			return r && (r = `<tbody>${r}</tbody>`), `<table>
<thead>
` + t + `</thead>
` + r + `</table>
`;
		}
		tablerow({ text: e }) {
			return `<tr>
${e}</tr>
`;
		}
		tablecell(e) {
			let t = this.parser.parseInline(e.tokens), n = e.header ? "th" : "td";
			return (e.align ? `<${n} align="${e.align}">` : `<${n}>`) + t + `</${n}>
`;
		}
		strong({ tokens: e }) {
			return `<strong>${this.parser.parseInline(e)}</strong>`;
		}
		em({ tokens: e }) {
			return `<em>${this.parser.parseInline(e)}</em>`;
		}
		codespan({ text: e }) {
			return `<code>${O(e, !0)}</code>`;
		}
		br(e) {
			return "<br>";
		}
		del({ tokens: e }) {
			return `<del>${this.parser.parseInline(e)}</del>`;
		}
		link({ href: e, title: t, tokens: n }) {
			let r = this.parser.parseInline(n), i = J(e);
			if (i === null) return r;
			e = i;
			let s = "<a href=\"" + e + "\"";
			return t && (s += " title=\"" + O(t) + "\""), s += ">" + r + "</a>", s;
		}
		image({ href: e, title: t, text: n, tokens: r }) {
			r && (n = this.parser.parseInline(r, this.parser.textRenderer));
			let i = J(e);
			if (i === null) return O(n);
			e = i;
			let s = `<img src="${e}" alt="${O(n)}"`;
			return t && (s += ` title="${O(t)}"`), s += ">", s;
		}
		text(e) {
			return "tokens" in e && e.tokens ? this.parser.parseInline(e.tokens) : "escaped" in e && e.escaped ? e.text : O(e.text);
		}
	};
	var $ = class {
		strong({ text: e }) {
			return e;
		}
		em({ text: e }) {
			return e;
		}
		codespan({ text: e }) {
			return e;
		}
		del({ text: e }) {
			return e;
		}
		html({ text: e }) {
			return e;
		}
		text({ text: e }) {
			return e;
		}
		link({ text: e }) {
			return "" + e;
		}
		image({ text: e }) {
			return "" + e;
		}
		br() {
			return "";
		}
		checkbox({ raw: e }) {
			return e;
		}
	};
	var b = class u {
		options;
		renderer;
		textRenderer;
		constructor(e) {
			this.options = e || T, this.options.renderer = this.options.renderer || new y(), this.renderer = this.options.renderer, this.renderer.options = this.options, this.renderer.parser = this, this.textRenderer = new $();
		}
		static parse(e, t) {
			return new u(t).parse(e);
		}
		static parseInline(e, t) {
			return new u(t).parseInline(e);
		}
		parse(e) {
			this.renderer.parser = this;
			let t = "";
			for (let n = 0; n < e.length; n++) {
				let r = e[n];
				if (this.options.extensions?.renderers?.[r.type]) {
					let s = r, a = this.options.extensions.renderers[s.type].call({ parser: this }, s);
					if (a !== !1 || ![
						"space",
						"hr",
						"heading",
						"code",
						"table",
						"blockquote",
						"list",
						"html",
						"def",
						"paragraph",
						"text"
					].includes(s.type)) {
						t += a || "";
						continue;
					}
				}
				let i = r;
				switch (i.type) {
					case "space":
						t += this.renderer.space(i);
						break;
					case "hr":
						t += this.renderer.hr(i);
						break;
					case "heading":
						t += this.renderer.heading(i);
						break;
					case "code":
						t += this.renderer.code(i);
						break;
					case "table":
						t += this.renderer.table(i);
						break;
					case "blockquote":
						t += this.renderer.blockquote(i);
						break;
					case "list":
						t += this.renderer.list(i);
						break;
					case "checkbox":
						t += this.renderer.checkbox(i);
						break;
					case "html":
						t += this.renderer.html(i);
						break;
					case "def":
						t += this.renderer.def(i);
						break;
					case "paragraph":
						t += this.renderer.paragraph(i);
						break;
					case "text":
						t += this.renderer.text(i);
						break;
					default: {
						let s = "Token with \"" + i.type + "\" type was not found.";
						if (this.options.silent) return console.error(s), "";
						throw new Error(s);
					}
				}
			}
			return t;
		}
		parseInline(e, t = this.renderer) {
			this.renderer.parser = this;
			let n = "";
			for (let r = 0; r < e.length; r++) {
				let i = e[r];
				if (this.options.extensions?.renderers?.[i.type]) {
					let a = this.options.extensions.renderers[i.type].call({ parser: this }, i);
					if (a !== !1 || ![
						"escape",
						"html",
						"link",
						"image",
						"strong",
						"em",
						"codespan",
						"br",
						"del",
						"text"
					].includes(i.type)) {
						n += a || "";
						continue;
					}
				}
				let s = i;
				switch (s.type) {
					case "escape":
						n += t.text(s);
						break;
					case "html":
						n += t.html(s);
						break;
					case "link":
						n += t.link(s);
						break;
					case "image":
						n += t.image(s);
						break;
					case "checkbox":
						n += t.checkbox(s);
						break;
					case "strong":
						n += t.strong(s);
						break;
					case "em":
						n += t.em(s);
						break;
					case "codespan":
						n += t.codespan(s);
						break;
					case "br":
						n += t.br(s);
						break;
					case "del":
						n += t.del(s);
						break;
					case "text":
						n += t.text(s);
						break;
					default: {
						let a = "Token with \"" + s.type + "\" type was not found.";
						if (this.options.silent) return console.error(a), "";
						throw new Error(a);
					}
				}
			}
			return n;
		}
	};
	var P = class {
		options;
		block;
		constructor(e) {
			this.options = e || T;
		}
		static passThroughHooks = new Set([
			"preprocess",
			"postprocess",
			"processAllTokens",
			"emStrongMask"
		]);
		static passThroughHooksRespectAsync = new Set([
			"preprocess",
			"postprocess",
			"processAllTokens"
		]);
		preprocess(e) {
			return e;
		}
		postprocess(e) {
			return e;
		}
		processAllTokens(e) {
			return e;
		}
		emStrongMask(e) {
			return e;
		}
		provideLexer() {
			return this.block ? x.lex : x.lexInline;
		}
		provideParser() {
			return this.block ? b.parse : b.parseInline;
		}
	};
	var D = class {
		defaults = M();
		options = this.setOptions;
		parse = this.parseMarkdown(!0);
		parseInline = this.parseMarkdown(!1);
		Parser = b;
		Renderer = y;
		TextRenderer = $;
		Lexer = x;
		Tokenizer = w;
		Hooks = P;
		constructor(...e) {
			this.use(...e);
		}
		walkTokens(e, t) {
			let n = [];
			for (let r of e) switch (n = n.concat(t.call(this, r)), r.type) {
				case "table": {
					let i = r;
					for (let s of i.header) n = n.concat(this.walkTokens(s.tokens, t));
					for (let s of i.rows) for (let a of s) n = n.concat(this.walkTokens(a.tokens, t));
					break;
				}
				case "list": {
					let i = r;
					n = n.concat(this.walkTokens(i.items, t));
					break;
				}
				default: {
					let i = r;
					this.defaults.extensions?.childTokens?.[i.type] ? this.defaults.extensions.childTokens[i.type].forEach((s) => {
						let a = i[s].flat(Infinity);
						n = n.concat(this.walkTokens(a, t));
					}) : i.tokens && (n = n.concat(this.walkTokens(i.tokens, t)));
				}
			}
			return n;
		}
		use(...e) {
			let t = this.defaults.extensions || {
				renderers: {},
				childTokens: {}
			};
			return e.forEach((n) => {
				let r = { ...n };
				if (r.async = this.defaults.async || r.async || !1, n.extensions && (n.extensions.forEach((i) => {
					if (!i.name) throw new Error("extension name required");
					if ("renderer" in i) {
						let s = t.renderers[i.name];
						s ? t.renderers[i.name] = function(...a) {
							let o = i.renderer.apply(this, a);
							return o === !1 && (o = s.apply(this, a)), o;
						} : t.renderers[i.name] = i.renderer;
					}
					if ("tokenizer" in i) {
						if (!i.level || i.level !== "block" && i.level !== "inline") throw new Error("extension level must be 'block' or 'inline'");
						let s = t[i.level];
						s ? s.unshift(i.tokenizer) : t[i.level] = [i.tokenizer], i.start && (i.level === "block" ? t.startBlock ? t.startBlock.push(i.start) : t.startBlock = [i.start] : i.level === "inline" && (t.startInline ? t.startInline.push(i.start) : t.startInline = [i.start]));
					}
					"childTokens" in i && i.childTokens && (t.childTokens[i.name] = i.childTokens);
				}), r.extensions = t), n.renderer) {
					let i = this.defaults.renderer || new y(this.defaults);
					for (let s in n.renderer) {
						if (!(s in i)) throw new Error(`renderer '${s}' does not exist`);
						if (["options", "parser"].includes(s)) continue;
						let a = s, o = n.renderer[a], l = i[a];
						i[a] = (...p) => {
							let c = o.apply(i, p);
							return c === !1 && (c = l.apply(i, p)), c || "";
						};
					}
					r.renderer = i;
				}
				if (n.tokenizer) {
					let i = this.defaults.tokenizer || new w(this.defaults);
					for (let s in n.tokenizer) {
						if (!(s in i)) throw new Error(`tokenizer '${s}' does not exist`);
						if ([
							"options",
							"rules",
							"lexer"
						].includes(s)) continue;
						let a = s, o = n.tokenizer[a], l = i[a];
						i[a] = (...p) => {
							let c = o.apply(i, p);
							return c === !1 && (c = l.apply(i, p)), c;
						};
					}
					r.tokenizer = i;
				}
				if (n.hooks) {
					let i = this.defaults.hooks || new P();
					for (let s in n.hooks) {
						if (!(s in i)) throw new Error(`hook '${s}' does not exist`);
						if (["options", "block"].includes(s)) continue;
						let a = s, o = n.hooks[a], l = i[a];
						P.passThroughHooks.has(s) ? i[a] = (p) => {
							if (this.defaults.async && P.passThroughHooksRespectAsync.has(s)) return (async () => {
								let d = await o.call(i, p);
								return l.call(i, d);
							})();
							let c = o.call(i, p);
							return l.call(i, c);
						} : i[a] = (...p) => {
							if (this.defaults.async) return (async () => {
								let d = await o.apply(i, p);
								return d === !1 && (d = await l.apply(i, p)), d;
							})();
							let c = o.apply(i, p);
							return c === !1 && (c = l.apply(i, p)), c;
						};
					}
					r.hooks = i;
				}
				if (n.walkTokens) {
					let i = this.defaults.walkTokens, s = n.walkTokens;
					r.walkTokens = function(a) {
						let o = [];
						return o.push(s.call(this, a)), i && (o = o.concat(i.call(this, a))), o;
					};
				}
				this.defaults = {
					...this.defaults,
					...r
				};
			}), this;
		}
		setOptions(e) {
			return this.defaults = {
				...this.defaults,
				...e
			}, this;
		}
		lexer(e, t) {
			return x.lex(e, t ?? this.defaults);
		}
		parser(e, t) {
			return b.parse(e, t ?? this.defaults);
		}
		parseMarkdown(e) {
			return (n, r) => {
				let i = { ...r }, s = {
					...this.defaults,
					...i
				}, a = this.onError(!!s.silent, !!s.async);
				if (this.defaults.async === !0 && i.async === !1) return a(/* @__PURE__ */ new Error("marked(): The async option was set to true by an extension. Remove async: false from the parse options object to return a Promise."));
				if (typeof n > "u" || n === null) return a(/* @__PURE__ */ new Error("marked(): input parameter is undefined or null"));
				if (typeof n != "string") return a(/* @__PURE__ */ new Error("marked(): input parameter is of type " + Object.prototype.toString.call(n) + ", string expected"));
				if (s.hooks && (s.hooks.options = s, s.hooks.block = e), s.async) return (async () => {
					let o = s.hooks ? await s.hooks.preprocess(n) : n, p = await (s.hooks ? await s.hooks.provideLexer() : e ? x.lex : x.lexInline)(o, s), c = s.hooks ? await s.hooks.processAllTokens(p) : p;
					s.walkTokens && await Promise.all(this.walkTokens(c, s.walkTokens));
					let h = await (s.hooks ? await s.hooks.provideParser() : e ? b.parse : b.parseInline)(c, s);
					return s.hooks ? await s.hooks.postprocess(h) : h;
				})().catch(a);
				try {
					s.hooks && (n = s.hooks.preprocess(n));
					let l = (s.hooks ? s.hooks.provideLexer() : e ? x.lex : x.lexInline)(n, s);
					s.hooks && (l = s.hooks.processAllTokens(l)), s.walkTokens && this.walkTokens(l, s.walkTokens);
					let c = (s.hooks ? s.hooks.provideParser() : e ? b.parse : b.parseInline)(l, s);
					return s.hooks && (c = s.hooks.postprocess(c)), c;
				} catch (o) {
					return a(o);
				}
			};
		}
		onError(e, t) {
			return (n) => {
				if (n.message += `
Please report this to https://github.com/markedjs/marked.`, e) {
					let r = "<p>An error occurred:</p><pre>" + O(n.message + "", !0) + "</pre>";
					return t ? Promise.resolve(r) : r;
				}
				if (t) return Promise.reject(n);
				throw n;
			};
		}
	};
	var L = new D();
	function g(u, e) {
		return L.parse(u, e);
	}
	g.options = g.setOptions = function(u) {
		return L.setOptions(u), g.defaults = L.defaults, G(g.defaults), g;
	};
	g.getDefaults = M;
	g.defaults = T;
	g.use = function(...u) {
		return L.use(...u), g.defaults = L.defaults, G(g.defaults), g;
	};
	g.walkTokens = function(u, e) {
		return L.walkTokens(u, e);
	};
	g.parseInline = L.parseInline;
	g.Parser = b;
	g.parser = b.parse;
	g.Renderer = y;
	g.TextRenderer = $;
	g.Lexer = x;
	g.lexer = x.lex;
	g.Tokenizer = w;
	g.Hooks = P;
	g.parse = g;
	g.options;
	g.setOptions;
	g.use;
	g.walkTokens;
	g.parseInline;
	b.parse;
	x.lex;
	//#endregion
	//#region src/markdown.js
	var marked = new D({
		breaks: true,
		gfm: true
	});
	function renderMarkdown(text) {
		if (!text) return "";
		return purify.sanitize(marked.parse(text));
	}
	//#endregion
	//#region src/AiMessageBubble.svelte
	var root_1$14 = /* @__PURE__ */ from_html(`<div class="uc-ai-msg uc-ai-msg-user svelte-1ajl9q"><div class="uc-ai-msg-bubble uc-ai-msg-bubble-user svelte-1ajl9q"><span> </span></div> <div class="uc-ai-msg-meta svelte-1ajl9q"><span class="uc-ai-msg-time"> </span></div></div>`);
	var root_3$13 = /* @__PURE__ */ from_html(`<details class="uc-ai-reasoning svelte-1ajl9q"><summary class="uc-ai-reasoning-summary svelte-1ajl9q"><span aria-hidden="true" class="fa fa-brain"></span> <span>Reasoning</span></summary> <div class="uc-ai-reasoning-body svelte-1ajl9q"> </div></details>`);
	var root_4$7 = /* @__PURE__ */ from_html(`<span class="uc-ai-msg-tokens svelte-1ajl9q"><span aria-hidden="true" class="fa fa-dashboard"></span> </span>`);
	var root_5$6 = /* @__PURE__ */ from_html(`<span class="uc-ai-copy-feedback svelte-1ajl9q">Copied</span>`);
	var root_2$18 = /* @__PURE__ */ from_html(`<div class="uc-ai-msg uc-ai-msg-assistant svelte-1ajl9q"><!> <div class="uc-ai-msg-row svelte-1ajl9q"><div class="uc-ai-avatar svelte-1ajl9q" aria-hidden="true"><span></span></div> <div></div></div> <div class="uc-ai-msg-meta svelte-1ajl9q"><span class="uc-ai-msg-time"> </span> <!> <button type="button" class="uc-ai-copy-btn svelte-1ajl9q"><span aria-hidden="true"></span> <!></button> <!></div></div>`);
	var root_8$1 = /* @__PURE__ */ from_html(`<span> </span>`);
	var root_9 = /* @__PURE__ */ from_html(`<details class="uc-ai-tool-row svelte-1ajl9q"><summary class="svelte-1ajl9q"><span class="uc-ai-tool-label svelte-1ajl9q">Input</span> <span class="uc-ai-tool-preview svelte-1ajl9q"> </span></summary> <pre class="svelte-1ajl9q"><code> </code></pre></details>`);
	var root_10$1 = /* @__PURE__ */ from_html(`<div class="uc-ai-tool-row uc-ai-tool-running svelte-1ajl9q"><span class="uc-ai-tool-label svelte-1ajl9q">Output</span> <span class="uc-ai-tool-preview uc-ai-tool-pending svelte-1ajl9q">running…</span></div>`);
	var root_12 = /* @__PURE__ */ from_html(`<pre class="svelte-1ajl9q"><code> </code></pre>`);
	var root_13 = /* @__PURE__ */ from_html(`<div class="uc-ai-tool-text-output svelte-1ajl9q"> </div>`);
	var root_11 = /* @__PURE__ */ from_html(`<details class="uc-ai-tool-row svelte-1ajl9q"><summary class="svelte-1ajl9q"><span class="uc-ai-tool-label svelte-1ajl9q">Output</span> <span class="uc-ai-tool-preview svelte-1ajl9q"> </span></summary> <!></details>`);
	var root_7$3 = /* @__PURE__ */ from_html(`<div class="uc-ai-msg uc-ai-tool-step-wrap svelte-1ajl9q"><div><div class="uc-ai-tool-step-header svelte-1ajl9q"><span aria-hidden="true"><span></span></span> <span class="uc-ai-tool-step-name svelte-1ajl9q"> </span> <!></div> <div class="uc-ai-tool-step-body svelte-1ajl9q"><!> <!></div></div></div>`);
	var $$css$19 = {
		hash: "svelte-1ajl9q",
		code: "\n  /* ======================================================================\n     Layout\n     ----------------------------------------------------------------------\n     The assistant column used to have FOUR different left edges: the meta row\n     (2.6em at 0.7em font-size), the reasoning block (2.6em at 0.78em), the\n     bubble (avatar + gap) and the tool card (3.35em). Because `em` resolves\n     against each element's own font-size, none of those nominally-equal\n     indents produced the same pixel. The gutter is now owned by the COLUMN,\n     which is always at 1em, and the avatar hangs back into it — so every child\n     shares one edge no matter what it scales its text to.\n     ====================================================================== */.uc-ai-msg.svelte-1ajl9q {padding:var(--uc-chat-space-2) var(--uc-chat-space-3);}.uc-ai-msg-user.svelte-1ajl9q {display:flex;flex-direction:column;align-items:flex-end;}.uc-ai-msg-assistant.svelte-1ajl9q {display:flex;flex-direction:column;align-items:flex-start;padding-left:calc(var(--uc-chat-space-3) + var(--uc-chat-ai-gutter));}.uc-ai-msg-row.svelte-1ajl9q {display:flex;align-items:flex-start;gap:calc(var(--uc-chat-ai-gutter) - var(--uc-chat-ai-avatar-size));\n    /* Pull the avatar out into the gutter the column reserved for it. */margin-left:calc(-1 * var(--uc-chat-ai-gutter));max-width:calc(100% + var(--uc-chat-ai-gutter));}\n\n  /* ======================================================================\n     Avatar\n     ----------------------------------------------------------------------\n     Was a 135deg gradient between --uc-chat-color-31 and --uc-chat-color-41 —\n     a variable this component never defines, so the second stop fell back to\n     the first and the whole gradient painted a flat colour anyway. A drop\n     shadow on a 32px circle is decoration, not hierarchy. Both are gone; the\n     fill is the app's own primary, and the glyph its guaranteed contrast.\n     ====================================================================== */.uc-ai-avatar.svelte-1ajl9q {width:var(--uc-chat-ai-avatar-size);height:var(--uc-chat-ai-avatar-size);border-radius:50%;background-color:var(--uc-chat-accent-color);color:var(--uc-chat-accent-contrast-color);display:flex;align-items:center;justify-content:center;flex-shrink:0;\n    /* Must stay at 1em: `width: 2em` resolves against the element's OWN\n       font-size, so the old `font-size: 0.85em` quietly made the avatar 27px\n       wide while the column reserved a 32px gutter for it — which is how the\n       bubble ended up 5px left of everything below it. The glyph is scaled\n       instead. */font-size:1em;}.uc-ai-avatar.svelte-1ajl9q > span:where(.svelte-1ajl9q) {font-size:0.85em;line-height:1;}\n\n  /* ======================================================================\n     Bubbles\n     ----------------------------------------------------------------------\n     One radius for both sides. The old asymmetric \"tail\" corner (1em / 0.25em)\n     is the single most dated thing in the component and it made the two\n     speakers look like they came from different design systems.\n     ====================================================================== */.uc-ai-msg-bubble.svelte-1ajl9q {border-radius:var(--uc-chat-radius-lg);padding:var(--uc-chat-space-2) var(--uc-chat-space-3);line-height:1.5;font-size:0.9em;word-break:break-word;}.uc-ai-msg-bubble-user.svelte-1ajl9q {background-color:var(--uc-chat-accent-color);color:var(--uc-chat-accent-contrast-color);\n    /* Cap the measure so a pasted paragraph does not stretch edge to edge in a\n       wide region. */max-width:min(85%, 40em);}\n\n  /* Fill + hairline, and nothing else. It previously carried a fill AND a\n     border AND a shadow, so every message asked to be read as \"raised\" and the\n     transcript had no depth left to spend on anything that mattered. */.uc-ai-msg-bubble-assistant.svelte-1ajl9q {background-color:var(--uc-chat-surface-background-color);border:1px solid var(--uc-chat-component-border-color);max-width:min(100%, 48em);}\n\n  /* A failed turn is the one message that may shout: tinted fill plus a danger\n     outline, matching the guardrail strip's \"refusal\" treatment. The old\n     3px left rail is dropped — it was the same device the tool card used for\n     something entirely different. */.uc-ai-msg-bubble-error.svelte-1ajl9q {border-color:var(--uc-chat-danger-color);background-color:color-mix(\n      in srgb,\n      var(--uc-chat-danger-color) 8%,\n      var(--uc-chat-surface-background-color)\n    );}.uc-ai-msg-bubble-assistant p:first-child {margin-top:0;}.uc-ai-msg-bubble-assistant p:last-child {margin-bottom:0;}\n  /* Headings inside an answer were rendering at browser default sizes — an\n     `###` came out larger than the region title. Scale them to the bubble. */\n    .uc-ai-msg-bubble-assistant h1,\n    .uc-ai-msg-bubble-assistant h2,\n    .uc-ai-msg-bubble-assistant h3,\n    .uc-ai-msg-bubble-assistant h4\n   {font-size:1.05em;font-weight:600;line-height:1.35;margin:var(--uc-chat-space-3) 0 var(--uc-chat-space-1);}\n    .uc-ai-msg-bubble-assistant h1:first-child,\n    .uc-ai-msg-bubble-assistant h2:first-child,\n    .uc-ai-msg-bubble-assistant h3:first-child,\n    .uc-ai-msg-bubble-assistant h4:first-child\n   {margin-top:0;}\n  /* An inset payload is expressed by its fill alone — adding a border as well\n     made every code block look like a nested card. */.uc-ai-msg-bubble-assistant pre {background-color:var(--uc-chat-inset-background-color);padding:var(--uc-chat-space-2) var(--uc-chat-space-3);border-radius:var(--uc-chat-radius-md);overflow-x:auto;font-size:0.9em;font-family:var(--uc-chat-font-mono);}.uc-ai-msg-bubble-assistant code {font-size:0.9em;font-family:var(--uc-chat-font-mono);}.uc-ai-msg-bubble-assistant ul, .uc-ai-msg-bubble-assistant ol {padding-left:1.5em;margin:var(--uc-chat-space-2) 0;}.uc-ai-msg-bubble-assistant blockquote {border-left:2px solid var(--uc-chat-component-border-color);margin:var(--uc-chat-space-2) 0;padding:0.1em 0 0.1em var(--uc-chat-space-3);color:var(--uc-chat-component-text-muted-color);}\n\n  /* ======================================================================\n     Meta row\n     ====================================================================== */.uc-ai-msg-meta.svelte-1ajl9q {display:flex;gap:var(--uc-chat-space-2);margin-top:var(--uc-chat-space-1);\n    /* Aligned by the column, not by a hand-tuned indent that the 0.7em\n       font-size then silently shrank. */margin-left:0;font-size:0.7em;color:var(--uc-chat-component-text-muted-color);\n    /* Weight 200 exists in almost no UI font: it either snapped back to\n       regular or, in a theme with real light weights (Redwood), rendered\n       spindly. */font-weight:400;\n    /* The feedback comment box is a full-width child of this row, so it needs a\n       line to wrap onto rather than squeezing in beside the timestamp. */flex-wrap:wrap;align-items:center;min-height:1.6em;}.uc-ai-msg-tokens.svelte-1ajl9q {display:flex;align-items:center;gap:var(--uc-chat-space-1);}\n\n  /* Copy button: hover/focus-reveal but always in the tab order. */.uc-ai-copy-btn.svelte-1ajl9q {display:inline-flex;align-items:center;gap:var(--uc-chat-space-1);border:none;border-radius:var(--uc-chat-radius-sm);background:transparent;color:var(--uc-chat-component-text-muted-color);cursor:pointer;padding:0.15em 0.3em;font-size:1em;opacity:0;transition:opacity 0.15s;}.uc-ai-copy-btn.svelte-1ajl9q:hover {background-color:var(--uc-chat-hover-background-color);color:var(--uc-chat-component-text-title-color);}.uc-ai-msg-assistant.svelte-1ajl9q:hover .uc-ai-copy-btn:where(.svelte-1ajl9q),\n  .uc-ai-copy-btn.svelte-1ajl9q:focus-visible {opacity:1;}\n\n  /* Nothing hovers on a touch screen. */\n  @media (hover: none) {.uc-ai-copy-btn.svelte-1ajl9q {opacity:1;}\n  }.uc-ai-copy-feedback.svelte-1ajl9q {font-size:0.95em;}\n\n  /* ======================================================================\n     Reasoning (collapsible)\n     ====================================================================== */.uc-ai-reasoning.svelte-1ajl9q {margin:0 0 var(--uc-chat-space-1) 0;max-width:min(100%, 48em);font-size:0.78em;color:var(--uc-chat-component-text-muted-color);}.uc-ai-reasoning-summary.svelte-1ajl9q {display:inline-flex;align-items:center;gap:var(--uc-chat-space-1);cursor:pointer;user-select:none;padding:0.2em 0.5em;margin-left:-0.5em;border-radius:var(--uc-chat-radius-sm);list-style:none;font-style:italic;}.uc-ai-reasoning-summary.svelte-1ajl9q::-webkit-details-marker {display:none;}.uc-ai-reasoning-summary.svelte-1ajl9q::before {content:\"\\25B6\";font-size:0.65em;font-style:normal;transition:transform 0.15s;}.uc-ai-reasoning[open].svelte-1ajl9q .uc-ai-reasoning-summary:where(.svelte-1ajl9q)::before {transform:rotate(90deg);}.uc-ai-reasoning-summary.svelte-1ajl9q:hover {background-color:var(--uc-chat-hover-background-color);}\n\n  /* An inset panel, exactly like an expanded tool payload — both are \"the\n     detail behind the answer\", so they now look like one idea instead of two\n     (a quoted rule here, a filled panel there). */.uc-ai-reasoning-body.svelte-1ajl9q {margin-top:var(--uc-chat-space-1);padding:var(--uc-chat-space-2) var(--uc-chat-space-3);background-color:var(--uc-chat-inset-background-color);border-radius:var(--uc-chat-radius-md);font-style:italic;white-space:pre-wrap;line-height:1.5;max-height:14em;overflow-y:auto;}\n\n  @media (prefers-reduced-motion: reduce) {.uc-ai-reasoning-summary.svelte-1ajl9q::before {transition:none;}\n  }\n\n  /* ======================================================================\n     Tool step (combined call + result)\n     ----------------------------------------------------------------------\n     Was: white card, grey header bar, grey payloads, and a 3px coloured left\n     rail. The rail is generic \"AI product\" chrome that meant nothing (its\n     colour repeated what the status word already said), and the header grey\n     was literally the same token as the canvas behind the card. Now the card is\n     one surface divided by hairlines, and status lives in exactly one place:\n     the icon and the word next to it.\n     ====================================================================== */.uc-ai-tool-step-wrap.svelte-1ajl9q {display:flex;justify-content:flex-start;padding:var(--uc-chat-space-1) var(--uc-chat-space-3)\n      var(--uc-chat-space-1)\n      calc(var(--uc-chat-space-3) + var(--uc-chat-ai-gutter));}.uc-ai-tool-step.svelte-1ajl9q {width:100%;max-width:min(100%, 48em);\n    /* Deliberately unfilled. A tool call is supporting detail, so it must not\n       carry the same \"raised surface\" as the answer it supports — the two used\n       to be the identical white card and competed for the eye. */background-color:transparent;border:1px solid var(--uc-chat-component-border-color);border-radius:var(--uc-chat-radius-md);overflow:hidden;font-size:0.8em;line-height:1.4;}.uc-ai-tool-step.is-error.svelte-1ajl9q {border-color:color-mix(\n      in srgb,\n      var(--uc-chat-danger-color) 45%,\n      var(--uc-chat-component-border-color)\n    );}.uc-ai-tool-step-header.svelte-1ajl9q {display:flex;align-items:center;gap:var(--uc-chat-space-2);padding:var(--uc-chat-space-2) var(--uc-chat-space-3);border-bottom:1px solid var(--uc-chat-component-inner-border-color);}\n\n  /* A bare glyph. The circular chip it used to sit in was a third bordered box\n     inside an already bordered box inside a bordered card. */.uc-ai-tool-step-icon.svelte-1ajl9q {display:inline-flex;align-items:center;justify-content:center;color:var(--uc-chat-component-text-muted-color);flex-shrink:0;}.uc-ai-tool-step-icon.svelte-1ajl9q > .fa:where(.svelte-1ajl9q) {font-size:1em;line-height:1;}.uc-ai-tool-step-icon.is-success.svelte-1ajl9q {color:var(--uc-chat-success-color);}.uc-ai-tool-step-icon.is-error.svelte-1ajl9q {color:var(--uc-chat-danger-color);}.uc-ai-tool-step-icon.is-running.svelte-1ajl9q {color:var(--uc-chat-accent-color);}.uc-ai-tool-step-name.svelte-1ajl9q {font-family:var(--uc-chat-font-mono);font-weight:500;color:var(--uc-chat-component-text-title-color);flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}\n\n  /* Plain text, not a pill. The pastel pills (#e8f5e9 / #fce4ec / #e3f2fd) came\n     from no palette at all and stayed pastel in dark mode, where they glowed. */.uc-ai-tool-step-status.svelte-1ajl9q {font-size:0.9em;font-weight:500;color:var(--uc-chat-component-text-muted-color);text-transform:lowercase;flex-shrink:0;}.uc-ai-tool-step-status.is-error.svelte-1ajl9q {color:var(--uc-chat-danger-color);}.uc-ai-tool-step-status.is-running.svelte-1ajl9q {color:var(--uc-chat-accent-color);}.uc-ai-tool-step-body.svelte-1ajl9q {display:flex;flex-direction:column;}.uc-ai-tool-row.svelte-1ajl9q {border-top:1px solid var(--uc-chat-component-inner-border-color);}.uc-ai-tool-row.svelte-1ajl9q:first-child {border-top:none;}.uc-ai-tool-row.svelte-1ajl9q > summary:where(.svelte-1ajl9q),\n  .uc-ai-tool-running.svelte-1ajl9q {display:flex;align-items:baseline;gap:var(--uc-chat-space-2);padding:var(--uc-chat-space-2) var(--uc-chat-space-3);cursor:pointer;list-style:none;user-select:none;}.uc-ai-tool-running.svelte-1ajl9q {cursor:default;}.uc-ai-tool-row.svelte-1ajl9q > summary:where(.svelte-1ajl9q)::-webkit-details-marker {display:none;}.uc-ai-tool-row.svelte-1ajl9q > summary:where(.svelte-1ajl9q)::before {content:\"\\25B6\";font-size:0.65em;color:var(--uc-chat-component-text-muted-color);transition:transform 0.15s;flex-shrink:0;}.uc-ai-tool-row[open].svelte-1ajl9q > summary:where(.svelte-1ajl9q)::before {transform:rotate(90deg);}.uc-ai-tool-row.svelte-1ajl9q > summary:where(.svelte-1ajl9q):hover {background-color:var(--uc-chat-hover-background-color);}\n\n  @media (prefers-reduced-motion: reduce) {.uc-ai-tool-row.svelte-1ajl9q > summary:where(.svelte-1ajl9q)::before {transition:none;}\n  }.uc-ai-tool-label.svelte-1ajl9q {font-weight:600;color:var(--uc-chat-component-text-muted-color);text-transform:uppercase;font-size:0.8em;letter-spacing:0.06em;flex-shrink:0;min-width:4.75em;}.uc-ai-tool-preview.svelte-1ajl9q {font-family:var(--uc-chat-font-mono);color:var(--uc-chat-component-text-muted-color);font-size:0.95em;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;min-width:0;flex:1;}.uc-ai-tool-pending.svelte-1ajl9q {font-style:italic;}\n\n  /* Full-bleed inset panels rather than blocks indented under the label: the\n     fill already says \"this is the expanded payload\", so the indent was doing\n     the same job a second time and left a ragged left edge. */.uc-ai-tool-row.svelte-1ajl9q pre:where(.svelte-1ajl9q) {margin:0;padding:var(--uc-chat-space-2) var(--uc-chat-space-3);background-color:var(--uc-chat-inset-background-color);overflow-x:auto;font-family:var(--uc-chat-font-mono);font-size:0.95em;line-height:1.45;}.uc-ai-tool-text-output.svelte-1ajl9q {padding:var(--uc-chat-space-2) var(--uc-chat-space-3);background-color:var(--uc-chat-inset-background-color);white-space:pre-wrap;line-height:1.45;font-size:0.95em;}"
	};
	function AiMessageBubble($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css$19);
		let message = prop($$props, "message", 7), showReasoning = prop($$props, "showReasoning", 7, false), showTools = prop($$props, "showTools", 7, false), showMetadata = prop($$props, "showMetadata", 7, false), avatarIcon = prop($$props, "avatarIcon", 7, "fa fa-robot"), feedbackEnabled = prop($$props, "feedbackEnabled", 7, false), feedback = prop($$props, "feedback", 7, null), onFeedback = prop($$props, "onFeedback", 7, void 0);
		let formattedTime = /* @__PURE__ */ user_derived(() => formatTimeString(message().messageDate));
		let copied = /* @__PURE__ */ state(false);
		let copyTimer = null;
		async function copyMessage() {
			try {
				await navigator.clipboard.writeText(message().content ?? "");
				set(copied, true);
				clearTimeout(copyTimer);
				copyTimer = setTimeout(() => {
					set(copied, false);
				}, 1500);
			} catch (e) {
				debugError("Copy to clipboard failed", e);
			}
		}
		onDestroy(() => clearTimeout(copyTimer));
		function formatJson(str) {
			if (!str) return "";
			try {
				return JSON.stringify(JSON.parse(str), null, 2);
			} catch {
				return str;
			}
		}
		function isJson(str) {
			if (!str) return false;
			try {
				JSON.parse(str);
				return true;
			} catch {
				return false;
			}
		}
		function previewText(str, max = 60) {
			if (!str) return "";
			let s = String(str).trim();
			try {
				let parsed = JSON.parse(s);
				if (parsed && typeof parsed === "object") s = Object.entries(parsed).map(([k, v]) => {
					return `${k}: ${typeof v === "string" ? v : JSON.stringify(v)}`;
				}).join(", ");
				else s = String(parsed);
			} catch {}
			s = s.replace(/\s+/g, " ");
			return s.length > max ? `${s.slice(0, max - 1)}…` : s;
		}
		var $$exports = {
			get message() {
				return message();
			},
			set message($$value) {
				message($$value);
				flushSync();
			},
			get showReasoning() {
				return showReasoning();
			},
			set showReasoning($$value = false) {
				showReasoning($$value);
				flushSync();
			},
			get showTools() {
				return showTools();
			},
			set showTools($$value = false) {
				showTools($$value);
				flushSync();
			},
			get showMetadata() {
				return showMetadata();
			},
			set showMetadata($$value = false) {
				showMetadata($$value);
				flushSync();
			},
			get avatarIcon() {
				return avatarIcon();
			},
			set avatarIcon($$value = "fa fa-robot") {
				avatarIcon($$value);
				flushSync();
			},
			get feedbackEnabled() {
				return feedbackEnabled();
			},
			set feedbackEnabled($$value = false) {
				feedbackEnabled($$value);
				flushSync();
			},
			get feedback() {
				return feedback();
			},
			set feedback($$value = null) {
				feedback($$value);
				flushSync();
			},
			get onFeedback() {
				return onFeedback();
			},
			set onFeedback($$value = void 0) {
				onFeedback($$value);
				flushSync();
			}
		};
		var fragment = comment();
		var node = first_child(fragment);
		var consequent = ($$anchor) => {
			var div = root_1$14();
			var div_1 = child(div);
			var span = child(div_1);
			var text = child(span, true);
			reset(span);
			reset(div_1);
			var div_2 = sibling(div_1, 2);
			var span_1 = child(div_2);
			var text_1 = child(span_1, true);
			reset(span_1);
			reset(div_2);
			reset(div);
			template_effect(() => {
				set_text(text, message().content);
				set_text(text_1, get(formattedTime));
			});
			append($$anchor, div);
		};
		var consequent_5 = ($$anchor) => {
			var div_3 = root_2$18();
			var node_1 = child(div_3);
			var consequent_1 = ($$anchor) => {
				var details = root_3$13();
				var div_4 = sibling(child(details), 2);
				var text_2 = child(div_4, true);
				reset(div_4);
				reset(details);
				template_effect(() => set_text(text_2, message().reasoningContent));
				append($$anchor, details);
			};
			if_block(node_1, ($$render) => {
				if (showReasoning() && message().reasoningContent) $$render(consequent_1);
			});
			var div_5 = sibling(node_1, 2);
			var div_6 = child(div_5);
			var span_2 = child(div_6);
			reset(div_6);
			var div_7 = sibling(div_6, 2);
			let classes;
			html$2(div_7, () => renderMarkdown(message().content), true);
			reset(div_7);
			reset(div_5);
			var div_8 = sibling(div_5, 2);
			var span_3 = child(div_8);
			var text_3 = child(span_3, true);
			reset(span_3);
			var node_2 = sibling(span_3, 2);
			var consequent_2 = ($$anchor) => {
				var span_4 = root_4$7();
				var text_4 = sibling(child(span_4));
				reset(span_4);
				template_effect(() => set_text(text_4, ` ${message().inputTokens ?? 0 ?? ""} in / ${message().outputTokens ?? 0 ?? ""} out`));
				append($$anchor, span_4);
			};
			if_block(node_2, ($$render) => {
				if (showMetadata() && (message().inputTokens || message().outputTokens)) $$render(consequent_2);
			});
			var button = sibling(node_2, 2);
			var span_5 = child(button);
			let classes_1;
			var node_3 = sibling(span_5, 2);
			var consequent_3 = ($$anchor) => {
				append($$anchor, root_5$6());
			};
			if_block(node_3, ($$render) => {
				if (get(copied)) $$render(consequent_3);
			});
			reset(button);
			var node_4 = sibling(button, 2);
			var consequent_4 = ($$anchor) => {
				AiFeedbackControl($$anchor, {
					get feedback() {
						return feedback();
					},
					get onSubmit() {
						return onFeedback();
					}
				});
			};
			if_block(node_4, ($$render) => {
				if (feedbackEnabled() && onFeedback()) $$render(consequent_4);
			});
			reset(div_8);
			reset(div_3);
			template_effect(() => {
				set_class(span_2, 1, clsx(avatarIcon()), "svelte-1ajl9q");
				classes = set_class(div_7, 1, "uc-ai-msg-bubble uc-ai-msg-bubble-assistant svelte-1ajl9q", null, classes, { "uc-ai-msg-bubble-error": message().isError });
				set_attribute(div_7, "role", message().isError ? "alert" : void 0);
				set_text(text_3, get(formattedTime));
				set_attribute(button, "title", get(copied) ? "Copied" : "Copy message");
				set_attribute(button, "aria-label", get(copied) ? "Copied" : "Copy message");
				classes_1 = set_class(span_5, 1, "fa", null, classes_1, {
					"fa-copy": !get(copied),
					"fa-check": get(copied)
				});
			});
			delegated("click", button, copyMessage);
			append($$anchor, div_3);
		};
		var consequent_11 = ($$anchor) => {
			var div_9 = root_7$3();
			var div_10 = child(div_9);
			let classes_2;
			var div_11 = child(div_10);
			var span_7 = child(div_11);
			let classes_3;
			var span_8 = child(span_7);
			let classes_4;
			reset(span_7);
			var span_9 = sibling(span_7, 2);
			var text_5 = child(span_9, true);
			reset(span_9);
			var node_5 = sibling(span_9, 2);
			var consequent_6 = ($$anchor) => {
				var span_10 = root_8$1();
				let classes_5;
				var text_6 = child(span_10, true);
				reset(span_10);
				template_effect(() => {
					classes_5 = set_class(span_10, 1, "uc-ai-tool-step-status svelte-1ajl9q", null, classes_5, {
						"is-success": message().toolStatus === "success",
						"is-error": message().toolStatus === "error",
						"is-running": message().toolStatus === "running"
					});
					set_text(text_6, message().toolStatus);
				});
				append($$anchor, span_10);
			};
			if_block(node_5, ($$render) => {
				if (message().toolStatus) $$render(consequent_6);
			});
			reset(div_11);
			var div_12 = sibling(div_11, 2);
			var node_6 = child(div_12);
			var consequent_7 = ($$anchor) => {
				var details_1 = root_9();
				var summary = child(details_1);
				var span_11 = sibling(child(summary), 2);
				var text_7 = child(span_11, true);
				reset(span_11);
				reset(summary);
				var pre = sibling(summary, 2);
				var code = child(pre);
				var text_8 = child(code, true);
				reset(code);
				reset(pre);
				reset(details_1);
				template_effect(($0, $1) => {
					set_text(text_7, $0);
					set_text(text_8, $1);
				}, [() => previewText(message().toolInput), () => formatJson(message().toolInput)]);
				append($$anchor, details_1);
			};
			if_block(node_6, ($$render) => {
				if (message().toolInput) $$render(consequent_7);
			});
			var node_7 = sibling(node_6, 2);
			var consequent_8 = ($$anchor) => {
				append($$anchor, root_10$1());
			};
			var consequent_10 = ($$anchor) => {
				var details_2 = root_11();
				var summary_1 = child(details_2);
				var span_12 = sibling(child(summary_1), 2);
				var text_9 = child(span_12, true);
				reset(span_12);
				reset(summary_1);
				var node_8 = sibling(summary_1, 2);
				var consequent_9 = ($$anchor) => {
					var pre_1 = root_12();
					var code_1 = child(pre_1);
					var text_10 = child(code_1, true);
					reset(code_1);
					reset(pre_1);
					template_effect(($0) => set_text(text_10, $0), [() => formatJson(message().toolOutput)]);
					append($$anchor, pre_1);
				};
				var d = /* @__PURE__ */ user_derived(() => isJson(message().toolOutput));
				var alternate = ($$anchor) => {
					var div_14 = root_13();
					var text_11 = child(div_14, true);
					reset(div_14);
					template_effect(() => set_text(text_11, message().toolOutput));
					append($$anchor, div_14);
				};
				if_block(node_8, ($$render) => {
					if (get(d)) $$render(consequent_9);
					else $$render(alternate, -1);
				});
				reset(details_2);
				template_effect(($0) => set_text(text_9, $0), [() => previewText(message().toolOutput)]);
				append($$anchor, details_2);
			};
			if_block(node_7, ($$render) => {
				if (message().toolStatus === "running") $$render(consequent_8);
				else if (message().toolOutput) $$render(consequent_10, 1);
			});
			reset(div_12);
			reset(div_10);
			reset(div_9);
			template_effect(() => {
				classes_2 = set_class(div_10, 1, "uc-ai-tool-step svelte-1ajl9q", null, classes_2, {
					"is-running": message().toolStatus === "running",
					"is-error": message().toolStatus === "error"
				});
				classes_3 = set_class(span_7, 1, "uc-ai-tool-step-icon svelte-1ajl9q", null, classes_3, {
					"is-success": message().toolStatus === "success",
					"is-error": message().toolStatus === "error",
					"is-running": message().toolStatus === "running"
				});
				classes_4 = set_class(span_8, 1, "fa svelte-1ajl9q", null, classes_4, {
					"fa-wrench": message().toolStatus !== "running",
					"fa-spinner": message().toolStatus === "running",
					"fa-anim-spin": message().toolStatus === "running"
				});
				set_text(text_5, message().toolName ?? "tool");
			});
			append($$anchor, div_9);
		};
		if_block(node, ($$render) => {
			if (message().role === "user") $$render(consequent);
			else if (message().role === "assistant") $$render(consequent_5, 1);
			else if (showTools() && message().role === "tool_step") $$render(consequent_11, 2);
		});
		append($$anchor, fragment);
		return pop($$exports);
	}
	delegate(["click"]);
	create_custom_element(AiMessageBubble, {
		message: {},
		showReasoning: {},
		showTools: {},
		showMetadata: {},
		avatarIcon: {},
		feedbackEnabled: {},
		feedback: {},
		onFeedback: {}
	}, [], [], { mode: "open" });
	//#endregion
	//#region src/asciiAnim.js
	/**
	* Frame generators for the "AI is thinking" ASCII animations.
	*
	* Every generator is a pure function of (variant, tick): no `Math.random`, no
	* wall-clock reads, no module-level mutation. That keeps frames reproducible,
	* makes the art testable, and lets the reduced-motion path render a single
	* representative frame by asking for tick 0.
	*/
	var PLASMA_ROWS = 3;
	var PLASMA_COLS = 28;
	var PLASMA_RAMP = " .:-=+*#%@";
	var BRAILLE_CELLS = 14;
	var BRAILLE_RAMP = [
		"⠀",
		"⣀",
		"⣤",
		"⣶",
		"⣿"
	];
	var MATRIX_ROWS = 6;
	var MATRIX_COLS = 18;
	var MATRIX_GAP = 3;
	var MATRIX_TRAIL = 4;
	var MATRIX_GLYPHS = "01ABCDEFGHJKLMNPQRSTUVWXYZ<>*+=#%$&?/|";
	/**
	* Milliseconds between frames for a variant. `dots` is pure CSS and never
	* ticks, so it reports 0.
	* @param {string} variant
	* @returns {number}
	*/
	function frameIntervalMs(variant) {
		switch (variant) {
			case AI_ANIM_PLASMA: return 80;
			case AI_ANIM_BRAILLE: return 90;
			case AI_ANIM_MATRIX: return 110;
			default: return 0;
		}
	}
	/**
	* Normalize an arbitrary region-attribute value to one of a known set. Used for
	* every enum-ish indicator attribute, so an unknown or misconfigured value
	* always degrades to the documented default instead of rendering nothing.
	* @param {string} raw
	* @param {string[]} allowed
	* @param {string} fallback
	* @returns {string}
	*/
	function normalizeEnum(raw, allowed, fallback) {
		const val = String(raw || "").trim().toLowerCase();
		return allowed.includes(val) ? val : fallback;
	}
	/**
	* Normalize an arbitrary attribute value to a known variant.
	* @param {string} raw
	* @param {string} fallback
	* @returns {string}
	*/
	function normalizeVariant(raw, fallback) {
		return normalizeEnum(raw, AI_ANIM_VARIANTS, fallback);
	}
	/**
	* Render one frame of an ASCII animation.
	* @param {string} variant one of AI_ANIM_*
	* @param {number} tick monotonically increasing frame counter
	* @returns {string} newline-separated rows, or "" for non-ASCII variants
	*/
	function renderFrame(variant, tick) {
		switch (variant) {
			case AI_ANIM_PLASMA: return plasmaFrame(tick);
			case AI_ANIM_BRAILLE: return brailleFrame(tick);
			case AI_ANIM_MATRIX: return matrixFrame(tick);
			default: return "";
		}
	}
	/**
	* Three summed sines sampled through a density ramp, with a vertical envelope
	* so the middle row stays brightest — reads as a band of energy travelling
	* left to right.
	* @param {number} tick
	* @returns {string}
	*/
	function plasmaFrame(tick) {
		const t = tick * .5;
		const center = (PLASMA_ROWS - 1) / 2;
		const rows = [];
		for (let y = 0; y < PLASMA_ROWS; y++) {
			const envelope = 1 - Math.abs(y - center) / (center + 1) * .7;
			let row = "";
			for (let x = 0; x < PLASMA_COLS; x++) {
				const n = ((Math.sin(x * .35 + t * .25) + Math.sin(x * .13 - t * .19) + Math.sin((x + y * 2) * .22 + t * .31)) / 3 + 1) / 2 * envelope;
				const idx = Math.round(n * 9);
				row += PLASMA_RAMP[clamp(idx, 0, 9)];
			}
			rows.push(row);
		}
		return rows.join("\n");
	}
	/**
	* A single line of partially filled braille cells tracing a travelling wave.
	* @param {number} tick
	* @returns {string}
	*/
	function brailleFrame(tick) {
		const t = tick * .5;
		let row = "";
		for (let x = 0; x < BRAILLE_CELLS; x++) {
			const v = .75 * Math.sin(x * .55 - t * .38) + .25 * Math.sin(x * .21 + t * .22);
			const idx = Math.round((v + 1) / 2 * (BRAILLE_RAMP.length - 1));
			row += BRAILLE_RAMP[clamp(idx, 0, BRAILLE_RAMP.length - 1)];
		}
		return row;
	}
	/**
	* Glyph columns raining downward. Each column gets a per-column speed and phase
	* from a hash of its index, so the columns desynchronize without randomness.
	* @param {number} tick
	* @returns {string}
	*/
	function matrixFrame(tick) {
		const cycle = MATRIX_ROWS + MATRIX_GAP;
		const bucket = Math.floor(tick / 3);
		const rows = [];
		for (let y = 0; y < MATRIX_ROWS; y++) {
			let row = "";
			for (let x = 0; x < MATRIX_COLS; x++) {
				const h = hash(x);
				const speed = .45 + h % 5 * .12;
				const phase = h % cycle;
				const dist = Math.floor(tick * speed + phase) % cycle - y;
				if (dist < 0 || dist > MATRIX_TRAIL) row += " ";
				else if (dist === MATRIX_TRAIL) row += "·";
				else {
					const r = mulberry32(hash(x * 7919 + y * 104729 + bucket * 13));
					row += MATRIX_GLYPHS[Math.floor(r * 38)];
				}
			}
			rows.push(row);
		}
		return rows.join("\n");
	}
	/**
	* Cheap integer avalanche hash (xorshift-multiply), always non-negative.
	* @param {number} n
	* @returns {number}
	*/
	function hash(n) {
		let h = n | 0;
		h = Math.imul(h ^ h >>> 16, 73244475);
		h = Math.imul(h ^ h >>> 16, 73244475);
		h = h ^ h >>> 16;
		return h >>> 0;
	}
	/**
	* mulberry32 seeded PRNG, one draw per call.
	* @param {number} seed
	* @returns {number} in [0, 1)
	*/
	function mulberry32(seed) {
		let a = seed + 1831565813 | 0;
		a = Math.imul(a ^ a >>> 15, 1 | a);
		a = a + Math.imul(a ^ a >>> 7, 61 | a) ^ a;
		return ((a ^ a >>> 14) >>> 0) / 4294967296;
	}
	/**
	* @param {number} n
	* @param {number} lo
	* @param {number} hi
	* @returns {number}
	*/
	function clamp(n, lo, hi) {
		return n < lo ? lo : n > hi ? hi : n;
	}
	//#endregion
	//#region src/AiThinkingIndicator.svelte
	var root_1$13 = /* @__PURE__ */ from_html(`<div class="uc-ai-typing-dots svelte-1wtb16" aria-hidden="true"><span class="svelte-1wtb16"></span><span class="svelte-1wtb16"></span><span class="svelte-1wtb16"></span></div>`);
	var root_2$17 = /* @__PURE__ */ from_html(`<pre aria-hidden="true"> </pre>`);
	var root_4$6 = /* @__PURE__ */ from_html(`<span class="uc-ai-typing-elapsed svelte-1wtb16"> </span>`);
	var root_3$12 = /* @__PURE__ */ from_html(`<div class="uc-ai-typing-phase svelte-1wtb16" aria-hidden="true"><span class="svelte-1wtb16"> </span> <!></div>`);
	var root$16 = /* @__PURE__ */ from_html(`<div class="uc-ai-typing svelte-1wtb16"><div class="uc-ai-avatar svelte-1wtb16" aria-hidden="true"><span></span></div> <div class="uc-ai-typing-bubble svelte-1wtb16"><!> <!></div> <span class="uc-visually-hidden svelte-1wtb16" role="status"> </span></div>`);
	var $$css$18 = {
		hash: "svelte-1wtb16",
		code: "\n  /* Sits on the same assistant gutter as a real message, so a turn starting\n     does not shift the column. */.uc-ai-typing.svelte-1wtb16 {display:flex;align-items:center;gap:calc(var(--uc-chat-ai-gutter) - var(--uc-chat-ai-avatar-size));padding:var(--uc-chat-space-2) var(--uc-chat-space-3);}\n\n  /* Matches the assistant avatar in AiMessageBubble — flat accent fill, no\n     no-op gradient, no shadow. */.uc-ai-avatar.svelte-1wtb16 {width:var(--uc-chat-ai-avatar-size);height:var(--uc-chat-ai-avatar-size);border-radius:50%;background-color:var(--uc-chat-accent-color);color:var(--uc-chat-accent-contrast-color);display:flex;align-items:center;justify-content:center;flex-shrink:0;\n    /* See AiMessageBubble: the box must be measured at 1em or it drifts out of\n       the gutter the column reserved for it. */font-size:1em;}.uc-ai-avatar.svelte-1wtb16 > span:where(.svelte-1wtb16) {font-size:0.85em;line-height:1;}\n\n  /* Same fill, border and radius as an assistant bubble: this IS the answer,\n     just not written yet. It previously had a 0.5px border (a sub-pixel width\n     that renders inconsistently), a different radius and a shadow. */.uc-ai-typing-bubble.svelte-1wtb16 {padding:var(--uc-chat-space-2) var(--uc-chat-space-3);background-color:var(--uc-chat-surface-background-color);border:1px solid var(--uc-chat-component-border-color);border-radius:var(--uc-chat-radius-lg);max-width:100%;overflow:hidden;}.uc-ai-typing-dots.svelte-1wtb16 {display:flex;gap:var(--uc-chat-space-1);padding-block:0.2em;}.uc-ai-typing-dots.svelte-1wtb16 > span:where(.svelte-1wtb16) {width:0.45em;height:0.45em;border-radius:50%;background-color:var(--uc-chat-component-text-muted-color);\n    animation: svelte-1wtb16-uc-ai-dot-bounce 1.4s infinite ease-in-out both;}.uc-ai-typing-dots.svelte-1wtb16 > span:where(.svelte-1wtb16):nth-child(1) {animation-delay:-0.32s;}.uc-ai-typing-dots.svelte-1wtb16 > span:where(.svelte-1wtb16):nth-child(2) {animation-delay:-0.16s;}\n\n  @keyframes svelte-1wtb16-uc-ai-dot-bounce {\n    0%, 80%, 100% {\n      transform: scale(0.6);\n      opacity: 0.4;\n    }\n    40% {\n      transform: scale(1);\n      opacity: 1;\n    }\n  }\n\n  /* The art is decorative: never wrap it (a wrapped frame is nonsense), clip in\n     narrow containers, and keep it out of text selections. */.uc-ai-ascii.svelte-1wtb16 {margin:0;font-family:var(--uc-chat-font-mono);font-size:0.7em;line-height:1.05;letter-spacing:0.02em;white-space:pre;overflow:hidden;color:var(--uc-chat-accent-color);user-select:none;}\n\n  /* Braille glyphs carry their own internal padding and read as too small at\n     the density-ramp size. */.uc-ai-ascii.is-braille.svelte-1wtb16 {font-size:1em;line-height:1.2;letter-spacing:0;}.uc-ai-typing-phase.svelte-1wtb16 {display:flex;align-items:baseline;gap:var(--uc-chat-space-2);margin-top:var(--uc-chat-space-1);font-size:0.75em;color:var(--uc-chat-component-text-muted-color);}.uc-ai-typing-elapsed.svelte-1wtb16 {opacity:0.7;font-variant-numeric:tabular-nums;}.uc-visually-hidden.svelte-1wtb16 {position:absolute;width:1px;height:1px;margin:-1px;padding:0;overflow:hidden;clip:rect(0 0 0 0);clip-path:inset(50%);white-space:nowrap;border:0;}\n\n  @media (prefers-reduced-motion: reduce) {.uc-ai-typing-dots.svelte-1wtb16 > span:where(.svelte-1wtb16) {\n      animation: none;opacity:0.55;}\n  }"
	};
	function AiThinkingIndicator($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css$18);
		let variant = prop($$props, "variant", 7, AI_ANIM_DOTS), detail = prop($$props, "detail", 7, AI_DETAIL_TOOLS), avatarIcon = prop($$props, "avatarIcon", 7, "fa fa-robot"), toolName = prop($$props, "toolName", 7, "");
		let animVariant = /* @__PURE__ */ user_derived(() => normalizeVariant(variant(), AI_ANIM_DOTS));
		let detailLevel = /* @__PURE__ */ user_derived(() => normalizeEnum(detail(), AI_DETAIL_LEVELS, AI_DETAIL_TOOLS));
		let startedAt = Date.now();
		let reducedMotion = prefersReducedMotion();
		let frameTick = /* @__PURE__ */ state(0);
		let elapsed = /* @__PURE__ */ state(0);
		let frame = /* @__PURE__ */ user_derived(() => renderFrame(get(animVariant), reducedMotion ? 0 : get(frameTick)));
		let phaseText = /* @__PURE__ */ user_derived(() => get(detailLevel) === "tools" && toolName() ? "Running a tool…" : "Thinking…");
		let elapsedText = /* @__PURE__ */ user_derived(() => get(elapsed) >= 2 ? `${get(elapsed)}s` : "");
		let showPhase = /* @__PURE__ */ user_derived(() => get(detailLevel) !== "off");
		function prefersReducedMotion() {
			if (typeof window === "undefined" || !window.matchMedia) return false;
			return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
		}
		user_effect(() => {
			let intervalMs = frameIntervalMs(get(animVariant));
			if (reducedMotion || intervalMs === 0) return;
			let id = setInterval(() => {
				set(frameTick, get(frameTick) + 1);
			}, intervalMs);
			return () => clearInterval(id);
		});
		user_effect(() => {
			let id = setInterval(() => {
				set(elapsed, Math.floor((Date.now() - startedAt) / 1e3), true);
			}, 1e3);
			return () => clearInterval(id);
		});
		var $$exports = {
			get variant() {
				return variant();
			},
			set variant($$value = AI_ANIM_DOTS) {
				variant($$value);
				flushSync();
			},
			get detail() {
				return detail();
			},
			set detail($$value = AI_DETAIL_TOOLS) {
				detail($$value);
				flushSync();
			},
			get avatarIcon() {
				return avatarIcon();
			},
			set avatarIcon($$value = "fa fa-robot") {
				avatarIcon($$value);
				flushSync();
			},
			get toolName() {
				return toolName();
			},
			set toolName($$value = "") {
				toolName($$value);
				flushSync();
			}
		};
		var div = root$16();
		var div_1 = child(div);
		var span = child(div_1);
		reset(div_1);
		var div_2 = sibling(div_1, 2);
		var node = child(div_2);
		var consequent = ($$anchor) => {
			append($$anchor, root_1$13());
		};
		var alternate = ($$anchor) => {
			var pre = root_2$17();
			let classes;
			var text = child(pre, true);
			reset(pre);
			template_effect(() => {
				classes = set_class(pre, 1, "uc-ai-ascii svelte-1wtb16", null, classes, { "is-braille": get(animVariant) === AI_ANIM_BRAILLE });
				set_attribute(pre, "data-variant", get(animVariant));
				set_text(text, get(frame));
			});
			append($$anchor, pre);
		};
		if_block(node, ($$render) => {
			if (get(animVariant) === "dots") $$render(consequent);
			else $$render(alternate, -1);
		});
		var node_1 = sibling(node, 2);
		var consequent_2 = ($$anchor) => {
			var div_4 = root_3$12();
			var span_1 = child(div_4);
			var text_1 = child(span_1, true);
			reset(span_1);
			var node_2 = sibling(span_1, 2);
			var consequent_1 = ($$anchor) => {
				var span_2 = root_4$6();
				var text_2 = child(span_2, true);
				reset(span_2);
				template_effect(() => set_text(text_2, get(elapsedText)));
				append($$anchor, span_2);
			};
			if_block(node_2, ($$render) => {
				if (get(elapsedText)) $$render(consequent_1);
			});
			reset(div_4);
			template_effect(() => set_text(text_1, get(phaseText)));
			append($$anchor, div_4);
		};
		if_block(node_1, ($$render) => {
			if (get(showPhase)) $$render(consequent_2);
		});
		reset(div_2);
		var span_3 = sibling(div_2, 2);
		var text_3 = child(span_3, true);
		reset(span_3);
		reset(div);
		template_effect(() => {
			set_class(span, 1, clsx(avatarIcon()), "svelte-1wtb16");
			set_text(text_3, get(phaseText));
		});
		append($$anchor, div);
		return pop($$exports);
	}
	create_custom_element(AiThinkingIndicator, {
		variant: {},
		detail: {},
		avatarIcon: {},
		toolName: {}
	}, [], [], { mode: "open" });
	//#endregion
	//#region src/state.svelte.js
	var STATE_KEY = Symbol("chatState");
	var AI_STATE_KEY = Symbol("aiChatState");
	var CHANNEL_STATE_KEY = Symbol("channelChatState");
	function createChatState() {
		const state = proxy({
			leftPaneMode: LP_MODE_CHATS,
			rightPaneMode: RP_MODE_CHAT,
			currChat: {
				roomId: null,
				roomName: null,
				userIds: []
			},
			newGroupUsers: []
		});
		setContext(STATE_KEY, state);
		return state;
	}
	function getChatState() {
		return getContext(STATE_KEY);
	}
	function openChat(chatState, { roomId, roomName, userIds }) {
		const logPrefix = getLogPrefix();
		apex.debug.trace(logPrefix, "openChat", {
			roomId,
			roomName,
			userIds
		});
		chatState.currChat = {
			roomId,
			roomName,
			userIds
		};
	}
	function createAiChatState({ sessionId, agentCode, agentVersion }) {
		const state = proxy({
			sessionId: sessionId || null,
			isProcessing: false,
			agentCode: agentCode || null,
			agentVersion: agentVersion || null,
			sessionTitle: null,
			feedback: null,
			guardrail: null,
			contextConflict: false
		});
		setContext(AI_STATE_KEY, state);
		return state;
	}
	function getAiChatState() {
		return getContext(AI_STATE_KEY);
	}
	function createChannelState() {
		const state = proxy({
			channels: [],
			currentChannel: null,
			activeThread: null
		});
		setContext(CHANNEL_STATE_KEY, state);
		return state;
	}
	function getChannelState() {
		return getContext(CHANNEL_STATE_KEY);
	}
	function openChannel(channelState, channel) {
		const logPrefix = getLogPrefix();
		apex.debug.trace(logPrefix, "openChannel", {
			channelId: channel.channelId,
			channelName: channel.channelName
		});
		channelState.currentChannel = channel;
		channelState.activeThread = null;
	}
	function openThread(channelState, parentMessage) {
		const logPrefix = getLogPrefix();
		apex.debug.trace(logPrefix, "openThread", { messageId: parentMessage.messageId });
		channelState.activeThread = { parentMessage };
	}
	function closeThread(channelState) {
		channelState.activeThread = null;
	}
	//#endregion
	//#region src/AiMessageList.svelte
	var root_2$16 = /* @__PURE__ */ from_html(`<div class="uc-ai-empty-state svelte-1mci0g4" role="alert"><span aria-hidden="true" class="fa fa-exclamation-triangle uc-ai-empty-icon svelte-1mci0g4"></span> <p class="svelte-1mci0g4">Could not load the conversation.</p> <button type="button" class="t-Button t-Button--small">Retry</button></div>`);
	var root_5$5 = /* @__PURE__ */ from_html(`<button type="button" class="uc-ai-suggested-prompt svelte-1mci0g4"> </button>`);
	var root_4$5 = /* @__PURE__ */ from_html(`<div class="uc-ai-suggested-prompts svelte-1mci0g4"></div>`);
	var root_3$11 = /* @__PURE__ */ from_html(`<div class="uc-ai-welcome svelte-1mci0g4"><!> <!></div>`);
	var root_7$2 = /* @__PURE__ */ from_html(`<div class="uc-ai-day-info svelte-1mci0g4"><span class="uc-ai-day-info-text svelte-1mci0g4"> </span></div>`);
	var root_6$4 = /* @__PURE__ */ from_html(`<!> <!>`, 1);
	var root$15 = /* @__PURE__ */ from_html(`<div class="uc-ai-message-list svelte-1mci0g4"><!> <!> <!> <!></div>`);
	var $$css$17 = {
		hash: "svelte-1mci0g4",
		code: ".uc-ai-message-list.svelte-1mci0g4 {height:100%;overflow-y:auto;display:flex;flex-direction:column;padding-block:var(--uc-chat-space-2);}.uc-ai-empty-state.svelte-1mci0g4 {flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;color:var(--uc-chat-component-text-muted-color);gap:var(--uc-chat-space-2);}.uc-ai-empty-icon.svelte-1mci0g4 {font-size:2.5em;opacity:0.4;}.uc-ai-empty-state.svelte-1mci0g4 > p:where(.svelte-1mci0g4) {font-size:1em;\n    /* Weight 300 is a light face most UI stacks do not ship, so this either\n       snapped to regular or rendered spindly depending on the theme font. */font-weight:400;margin:0;}\n\n  /* Welcome greeting: top-aligned so it reads like the first chat message. */.uc-ai-welcome.svelte-1mci0g4 {display:flex;flex-direction:column;}\n\n  /* The greeting is canned copy, not something that was said at a moment: the\n     meta row was stamping it with the page-load time and offering to copy it.\n     Hidden here rather than in the bubble, so real messages are untouched. */.uc-ai-welcome.svelte-1mci0g4 .uc-ai-msg-meta {display:none;}\n\n  /* Aligned to the same assistant gutter as every bubble, reasoning block and\n     tool card — the chips used to sit on a fourth, hand-tuned left edge. */.uc-ai-suggested-prompts.svelte-1mci0g4 {display:flex;flex-wrap:wrap;justify-content:flex-start;gap:var(--uc-chat-space-2);padding:var(--uc-chat-space-1) var(--uc-chat-space-3) 0\n      calc(var(--uc-chat-space-3) + var(--uc-chat-ai-gutter));max-width:48em;}\n\n  /* Border + fill and nothing else. The shadow made a chip look like a raised\n     card competing with the answer next to it. */.uc-ai-suggested-prompt.svelte-1mci0g4 {border:1px solid var(--uc-chat-component-border-color);background-color:var(--uc-chat-surface-background-color);color:var(--uc-chat-component-text-title-color);border-radius:var(--uc-chat-radius-pill);padding:0.4em 0.9em;font-size:0.85em;line-height:1.35;font-family:var(--uc-chat-font-base);cursor:pointer;transition:border-color 0.15s,\n      background-color 0.15s;}\n\n  /* Hovering a chip is an invitation to send it, so the accent belongs here —\n     it was previously the only hover in the pane that did not react at all. */.uc-ai-suggested-prompt.svelte-1mci0g4:hover {border-color:var(--uc-chat-accent-color);color:var(--uc-chat-accent-color);}.uc-ai-suggested-prompt.svelte-1mci0g4:focus-visible {outline:2px solid var(--uc-chat-accent-color);outline-offset:1px;}\n\n  @media (prefers-reduced-motion: reduce) {.uc-ai-suggested-prompt.svelte-1mci0g4 {transition:none;}\n  }\n\n  /* A centred date chip rather than text notched out of a horizontal rule. The\n     notch trick needs an opaque backdrop to paint over the line, and the canvas\n     is now a translucent tint — repainting it would have shown as a lighter\n     patch. A chip also matches the pill language the prompt chips already use. */.uc-ai-day-info.svelte-1mci0g4 {text-align:center;margin:var(--uc-chat-space-3) var(--uc-chat-space-3)\n      var(--uc-chat-space-2);}.uc-ai-day-info-text.svelte-1mci0g4 {display:inline-block;padding:0.2em 0.7em;font-size:0.7em;line-height:1.4;color:var(--uc-chat-component-text-muted-color);background-color:var(--uc-chat-surface-background-color);border:1px solid var(--uc-chat-component-border-color);border-radius:var(--uc-chat-radius-pill);font-weight:400;}\n\n  /* The thinking indicator owns its own styles — see AiThinkingIndicator.svelte. */"
	};
	function AiMessageList($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css$17);
		let regionId = prop($$props, "regionId", 7), showReasoning = prop($$props, "showReasoning", 7, false), showTools = prop($$props, "showTools", 7, false), showMetadata = prop($$props, "showMetadata", 7, false), avatarIcon = prop($$props, "avatarIcon", 7, "fa fa-robot"), suggestedPrompts = prop($$props, "suggestedPrompts", 23, () => []), onPromptClick = prop($$props, "onPromptClick", 7, void 0), welcomeMessage = prop($$props, "welcomeMessage", 7, ""), thinkingAnimation = prop($$props, "thinkingAnimation", 7, AI_ANIM_DOTS), thinkingDetail = prop($$props, "thinkingDetail", 7, AI_DETAIL_TOOLS), onGuardrail = prop($$props, "onGuardrail", 7, void 0), collectFeedback = prop($$props, "collectFeedback", 7, false), onFeedback = prop($$props, "onFeedback", 7, void 0);
		let welcomeText = /* @__PURE__ */ user_derived(() => welcomeMessage()?.trim() || "Ask me anything...");
		let welcomeDate = (/* @__PURE__ */ new Date()).toISOString();
		let welcomeItem = /* @__PURE__ */ user_derived(() => ({
			messageId: "__welcome__",
			role: AI_ROLE_ASSISTANT,
			content: get(welcomeText),
			messageDate: welcomeDate
		}));
		const aiState = getAiChatState();
		const NEAR_BOTTOM_PX = 100;
		const LOAD_OLDER_THRESHOLD_PX = 40;
		/** @type {aiMessageObject[]} */
		let items = /* @__PURE__ */ state(proxy([]));
		let loading = /* @__PURE__ */ state(false);
		let allFetched = /* @__PURE__ */ state(false);
		let loadError = /* @__PURE__ */ state(false);
		let scrollContainer = /* @__PURE__ */ state(void 0);
		let displayItems = /* @__PURE__ */ user_derived(() => {
			let reordered = [];
			let pendingAssistant = null;
			let pendingTools = [];
			function flush() {
				for (let t of pendingTools) reordered.push(t);
				if (pendingAssistant) reordered.push(pendingAssistant);
				pendingTools = [];
				pendingAssistant = null;
			}
			for (let msg of get(items)) if (msg.role === "assistant") {
				flush();
				pendingAssistant = msg;
			} else if (msg.role === "tool_call" || msg.role === "tool_result") if (pendingAssistant) pendingTools.push(msg);
			else reordered.push(msg);
			else {
				flush();
				reordered.push(msg);
			}
			flush();
			let merged = [];
			let i = 0;
			while (i < reordered.length) {
				let cur = reordered[i];
				if (cur.role !== "tool_call" && cur.role !== "tool_result") {
					merged.push(cur);
					i += 1;
					continue;
				}
				let runStart = i;
				while (i < reordered.length && (reordered[i].role === "tool_call" || reordered[i].role === "tool_result")) i += 1;
				let run = reordered.slice(runStart, i);
				let results = run.filter((r) => r.role === AI_ROLE_TOOL_RESULT);
				let consumed = new Array(results.length).fill(false);
				for (let r of run) {
					if (r.role !== "tool_call") continue;
					let k = results.findIndex((res, idx) => !consumed[idx] && res.toolName === r.toolName);
					if (k >= 0) {
						consumed[k] = true;
						merged.push({
							messageId: `step-${r.messageId}`,
							role: AI_ROLE_TOOL_STEP,
							toolName: r.toolName,
							toolInput: r.toolInput,
							toolOutput: results[k].toolOutput,
							toolStatus: results[k].toolStatus || "success",
							messageDate: r.messageDate
						});
					} else merged.push({
						messageId: `step-${r.messageId}`,
						role: AI_ROLE_TOOL_STEP,
						toolName: r.toolName,
						toolInput: r.toolInput,
						toolStatus: "running",
						messageDate: r.messageDate
					});
				}
				results.forEach((res, idx) => {
					if (consumed[idx]) return;
					merged.push({
						messageId: `step-${res.messageId}`,
						role: AI_ROLE_TOOL_STEP,
						toolName: res.toolName,
						toolOutput: res.toolOutput,
						toolStatus: res.toolStatus || "success",
						messageDate: res.messageDate
					});
				});
			}
			return merged.map((m, idx) => ({
				...m,
				isDifferentDay: idx === 0 ? false : isDifferentDay(m.messageDate, merged[idx - 1].messageDate)
			}));
		});
		let runningToolName = /* @__PURE__ */ user_derived(() => {
			for (let i = get(displayItems).length - 1; i >= 0; i--) {
				let m = get(displayItems)[i];
				if (m.role === "tool_step" && m.toolStatus === "running") return m.toolName || "";
			}
			return "";
		});
		let lastAssistantId = /* @__PURE__ */ user_derived(() => {
			for (let i = get(displayItems).length - 1; i >= 0; i--) {
				let m = get(displayItems)[i];
				if (m.role === "assistant" && !m.isError) return m.messageId;
			}
			return null;
		});
		const persists = 50;
		async function fetchMessages(older = true) {
			if (!aiState.sessionId) return;
			if (older && get(allFetched)) return;
			set(loadError, false);
			set(loading, true);
			let lastMessageId = older ? get(items)[0]?.messageId : get(items)[get(items).length - 1]?.messageId;
			let initialLoad = older && lastMessageId == null;
			let res;
			try {
				res = await aiGetMessages({
					sessionId: aiState.sessionId,
					lastMessageId,
					olderOrNewer: older ? "older" : "newer",
					regionId: regionId()
				});
			} catch (e) {
				debugError("AiMessageList fetch failed", e);
				set(loadError, true);
				return;
			} finally {
				set(loading, false);
			}
			if (res.sessionTitle) aiState.sessionTitle = res.sessionTitle;
			if (res.feedback) aiState.feedback = res.feedback;
			if (initialLoad && res.guardrail) onGuardrail()?.(res.guardrail);
			if (!res.messages || res.messages.length === 0) {
				if (older) set(allFetched, true);
				return;
			}
			if (older && res.messages.length < persists) set(allFetched, true);
			let msgs = res.messages.reverse();
			if (older && get(items).length > 0) {
				let prevHeight = get(scrollContainer)?.scrollHeight ?? 0;
				let prevTop = get(scrollContainer)?.scrollTop ?? 0;
				set(items, [...msgs, ...get(items)], true);
				await tick();
				if (get(scrollContainer)) get(scrollContainer).scrollTop = get(scrollContainer).scrollHeight - prevHeight + prevTop;
			} else if (older) set(items, [...msgs, ...get(items)], true);
			else set(items, [...get(items), ...msgs], true);
			if (initialLoad) reconstructTurnError(res.turn);
			debugTrace("AiMessageList fetched", {
				count: msgs.length,
				older,
				total: get(items).length
			});
		}
		function reconstructTurnError(turn) {
			if (!turn || turn.status !== "error") return;
			let uid = turn.userMessageId;
			let detail = turn.guardrail ? guardrailMessage("hit", turn.guardrail) : turn.errorDetail;
			let marked = false;
			for (let m of get(items)) if (m.role === "assistant" && typeof m.messageId === "number" && m.messageId > uid) {
				m.isError = true;
				if (detail) m.content = detail;
				marked = true;
			}
			if (marked) return;
			let id = `error-${uid}`;
			if (get(items).some((m) => m.messageId === id)) return;
			let userRow = get(items).find((m) => m.messageId === uid);
			get(items).push({
				messageId: id,
				role: AI_ROLE_ASSISTANT,
				content: detail || "This turn failed. Please try again.",
				isError: true,
				messageDate: userRow?.messageDate || (/* @__PURE__ */ new Date()).toISOString()
			});
		}
		function appendMessages(newMessages, { forceScroll = false } = {}) {
			if (!newMessages || newMessages.length === 0) return;
			let shouldScroll = forceScroll || isNearBottom();
			let appendedAny = false;
			for (let msg of newMessages) {
				let idx = get(items).findIndex((m) => m.messageId === msg.messageId);
				if (idx !== -1) get(items)[idx] = {
					...get(items)[idx],
					...msg
				};
				else {
					get(items).push(msg);
					appendedAny = true;
				}
			}
			if (appendedAny && shouldScroll) scrollToBottom();
		}
		function confirmMessage(tempId, realId) {
			let idx = get(items).findIndex((m) => m.messageId === tempId);
			if (idx === -1) return;
			let existing = get(items).findIndex((m) => m.messageId === realId);
			if (existing !== -1 && existing !== idx) {
				get(items).splice(idx, 1);
				return;
			}
			get(items)[idx].messageId = realId;
		}
		function removeRunningPlaceholders() {
			set(items, get(items).filter((m) => !(m.role === "tool_call" && m.toolStatus === "running")), true);
		}
		function adoptNewSession(sessionId) {
			set(items, [], true);
			set(allFetched, true);
			set(loadError, false);
			_prevSessionId = sessionId;
		}
		function hasMessages() {
			return get(items).length > 0;
		}
		function getFirstExchange() {
			let user = get(items).find((m) => m.role === AI_ROLE_USER);
			let assistant = get(items).find((m) => m.role === "assistant" && !m.isError);
			return {
				userText: user?.content || "",
				assistantText: assistant?.content || ""
			};
		}
		function isNearBottom() {
			if (!get(scrollContainer)) return true;
			return get(scrollContainer).scrollHeight - get(scrollContainer).scrollTop - get(scrollContainer).clientHeight < NEAR_BOTTOM_PX;
		}
		async function scrollToBottom(instant = false) {
			await tick();
			if (!get(scrollContainer)) return;
			get(scrollContainer).scrollTo({
				top: get(scrollContainer).scrollHeight,
				behavior: instant ? "auto" : "smooth"
			});
		}
		function handleScroll() {
			if (!get(scrollContainer)) return;
			if (get(scrollContainer).scrollTop < LOAD_OLDER_THRESHOLD_PX && !get(loading) && !get(allFetched)) fetchMessages(true);
		}
		let _prevSessionId = null;
		user_effect(() => {
			let sid = aiState.sessionId;
			if (sid && sid !== _prevSessionId) {
				_prevSessionId = sid;
				loadSession();
			}
		});
		let _wasProcessing = false;
		user_effect(() => {
			let processing = aiState.isProcessing;
			if (processing && !_wasProcessing && isNearBottom()) scrollToBottom();
			_wasProcessing = processing;
		});
		async function loadSession() {
			set(items, [], true);
			set(allFetched, false);
			await fetchMessages(true);
			scrollToBottom(true);
		}
		function retryLoad() {
			set(loadError, false);
			fetchMessages(true);
		}
		var $$exports = {
			appendMessages,
			confirmMessage,
			removeRunningPlaceholders,
			adoptNewSession,
			hasMessages,
			getFirstExchange,
			get regionId() {
				return regionId();
			},
			set regionId($$value) {
				regionId($$value);
				flushSync();
			},
			get showReasoning() {
				return showReasoning();
			},
			set showReasoning($$value = false) {
				showReasoning($$value);
				flushSync();
			},
			get showTools() {
				return showTools();
			},
			set showTools($$value = false) {
				showTools($$value);
				flushSync();
			},
			get showMetadata() {
				return showMetadata();
			},
			set showMetadata($$value = false) {
				showMetadata($$value);
				flushSync();
			},
			get avatarIcon() {
				return avatarIcon();
			},
			set avatarIcon($$value = "fa fa-robot") {
				avatarIcon($$value);
				flushSync();
			},
			get suggestedPrompts() {
				return suggestedPrompts();
			},
			set suggestedPrompts($$value = []) {
				suggestedPrompts($$value);
				flushSync();
			},
			get onPromptClick() {
				return onPromptClick();
			},
			set onPromptClick($$value = void 0) {
				onPromptClick($$value);
				flushSync();
			},
			get welcomeMessage() {
				return welcomeMessage();
			},
			set welcomeMessage($$value = "") {
				welcomeMessage($$value);
				flushSync();
			},
			get thinkingAnimation() {
				return thinkingAnimation();
			},
			set thinkingAnimation($$value = AI_ANIM_DOTS) {
				thinkingAnimation($$value);
				flushSync();
			},
			get thinkingDetail() {
				return thinkingDetail();
			},
			set thinkingDetail($$value = AI_DETAIL_TOOLS) {
				thinkingDetail($$value);
				flushSync();
			},
			get onGuardrail() {
				return onGuardrail();
			},
			set onGuardrail($$value = void 0) {
				onGuardrail($$value);
				flushSync();
			},
			get collectFeedback() {
				return collectFeedback();
			},
			set collectFeedback($$value = false) {
				collectFeedback($$value);
				flushSync();
			},
			get onFeedback() {
				return onFeedback();
			},
			set onFeedback($$value = void 0) {
				onFeedback($$value);
				flushSync();
			}
		};
		var div = root$15();
		var node = child(div);
		var consequent = ($$anchor) => {
			Spinner($$anchor, {});
		};
		if_block(node, ($$render) => {
			if (get(loading) && get(items).length === 0) $$render(consequent);
		});
		var node_1 = sibling(node, 2);
		var consequent_1 = ($$anchor) => {
			var div_1 = root_2$16();
			var button = sibling(child(div_1), 4);
			reset(div_1);
			delegated("click", button, retryLoad);
			append($$anchor, div_1);
		};
		var consequent_3 = ($$anchor) => {
			var div_2 = root_3$11();
			var node_2 = child(div_2);
			AiMessageBubble(node_2, {
				get message() {
					return get(welcomeItem);
				},
				get showReasoning() {
					return showReasoning();
				},
				get showTools() {
					return showTools();
				},
				get showMetadata() {
					return showMetadata();
				},
				get avatarIcon() {
					return avatarIcon();
				}
			});
			var node_3 = sibling(node_2, 2);
			var consequent_2 = ($$anchor) => {
				var div_3 = root_4$5();
				each(div_3, 21, suggestedPrompts, index, ($$anchor, prompt) => {
					var button_1 = root_5$5();
					var text = child(button_1, true);
					reset(button_1);
					template_effect(() => set_text(text, get(prompt)));
					delegated("click", button_1, () => onPromptClick()?.(get(prompt)));
					append($$anchor, button_1);
				});
				reset(div_3);
				append($$anchor, div_3);
			};
			if_block(node_3, ($$render) => {
				if (suggestedPrompts().length > 0) $$render(consequent_2);
			});
			reset(div_2);
			append($$anchor, div_2);
		};
		if_block(node_1, ($$render) => {
			if (get(loadError) && get(items).length === 0) $$render(consequent_1);
			else if (get(items).length === 0 && !get(loading)) $$render(consequent_3, 1);
		});
		var node_4 = sibling(node_1, 2);
		each(node_4, 17, () => get(displayItems), (message) => message.messageId, ($$anchor, message) => {
			var fragment_1 = root_6$4();
			var node_5 = first_child(fragment_1);
			var consequent_4 = ($$anchor) => {
				var div_4 = root_7$2();
				var span = child(div_4);
				var text_1 = child(span, true);
				reset(span);
				reset(div_4);
				template_effect(($0) => set_text(text_1, $0), [() => formatDateString(get(message).messageDate)]);
				append($$anchor, div_4);
			};
			if_block(node_5, ($$render) => {
				if (get(message).isDifferentDay) $$render(consequent_4);
			});
			var node_6 = sibling(node_5, 2);
			{
				let $0 = /* @__PURE__ */ user_derived(() => collectFeedback() && get(message).messageId === get(lastAssistantId));
				AiMessageBubble(node_6, {
					get message() {
						return get(message);
					},
					get showReasoning() {
						return showReasoning();
					},
					get showTools() {
						return showTools();
					},
					get showMetadata() {
						return showMetadata();
					},
					get avatarIcon() {
						return avatarIcon();
					},
					get feedbackEnabled() {
						return get($0);
					},
					get feedback() {
						return aiState.feedback;
					},
					get onFeedback() {
						return onFeedback();
					}
				});
			}
			append($$anchor, fragment_1);
		});
		var node_7 = sibling(node_4, 2);
		var consequent_5 = ($$anchor) => {
			AiThinkingIndicator($$anchor, {
				get variant() {
					return thinkingAnimation();
				},
				get detail() {
					return thinkingDetail();
				},
				get avatarIcon() {
					return avatarIcon();
				},
				get toolName() {
					return get(runningToolName);
				}
			});
		};
		if_block(node_7, ($$render) => {
			if (aiState.isProcessing) $$render(consequent_5);
		});
		reset(div);
		bind_this(div, ($$value) => set(scrollContainer, $$value), () => get(scrollContainer));
		event("scroll", div, handleScroll);
		append($$anchor, div);
		return pop($$exports);
	}
	delegate(["click"]);
	create_custom_element(AiMessageList, {
		regionId: {},
		showReasoning: {},
		showTools: {},
		showMetadata: {},
		avatarIcon: {},
		suggestedPrompts: {},
		onPromptClick: {},
		welcomeMessage: {},
		thinkingAnimation: {},
		thinkingDetail: {},
		onGuardrail: {},
		collectFeedback: {},
		onFeedback: {}
	}, [], [
		"appendMessages",
		"confirmMessage",
		"removeRunningPlaceholders",
		"adoptNewSession",
		"hasMessages",
		"getFirstExchange"
	], { mode: "open" });
	//#endregion
	//#region src/localModel.js
	/**
	* Conversation titles generated by the browser's built-in, on-device language
	* model (Chrome's Prompt API — `LanguageModel`, stable in Chrome 148).
	*
	* Nothing here ever leaves the device and nothing here is required: on any
	* browser without the API, on any failure, and on any timeout, every entry point
	* resolves to null and the chat keeps its configured header title.
	*
	* Two deliberate constraints:
	*  - We only ever run when availability is exactly "available". A "downloadable"
	*    model means Chrome would pull down several GB — never something a chat
	*    region should start on the user's behalf.
	*  - `LanguageModel.create()` needs transient user activation, which has long
	*    expired by the time an agent turn finishes polling. So the session is
	*    created eagerly from inside the send gesture (`warmUpTitleModel`) and
	*    reused for the lifetime of the page.
	*/
	var SYSTEM_PROMPT = "You name chat conversations. Given the first question and answer, reply with a title of at most six words that says what the conversation is about. Use the same language as the conversation. No quotes, no trailing punctuation, no prefix like 'Title:'.";
	var TITLE_SCHEMA = {
		type: "object",
		properties: { title: { type: "string" } },
		required: ["title"]
	};
	var MAX_USER_CHARS = 500;
	var MAX_ASSISTANT_CHARS = 1e3;
	var MAX_TITLE_CHARS = 80;
	var GENERATE_TIMEOUT_MS = 1e4;
	/** @type {string|null} cached result of LanguageModel.availability() */
	var availability = null;
	/** @type {Promise<any>|null} the one warmed-up session, reused page-wide */
	var sessionPromise = null;
	function getApi() {
		return typeof globalThis.LanguageModel === "undefined" ? null : globalThis.LanguageModel;
	}
	/**
	* Cache whether the on-device model is ready. Safe to call on mount — unlike
	* create(), availability() needs no user activation.
	* @returns {Promise<boolean>} true when a title can be generated
	*/
	async function probeTitleModel() {
		if (availability !== null) return availability === "available";
		const api = getApi();
		if (!api) {
			availability = "unsupported";
			return false;
		}
		try {
			availability = await api.availability({
				expectedInputs: [{ type: "text" }],
				expectedOutputs: [{ type: "text" }]
			});
		} catch (e) {
			debugInfo("Local title model availability check failed", e);
			availability = "unsupported";
		}
		debugInfo("Local title model availability", availability);
		return availability === "available";
	}
	/**
	* Create the model session while user activation is still live. Call this
	* synchronously from the send handler. No-op unless the cached availability
	* says the model is already on the device.
	*/
	function warmUpTitleModel() {
		if (sessionPromise || availability !== "available") return;
		const api = getApi();
		if (!api) return;
		sessionPromise = api.create({
			initialPrompts: [{
				role: "system",
				content: SYSTEM_PROMPT
			}],
			expectedInputs: [{ type: "text" }],
			expectedOutputs: [{ type: "text" }]
		}).catch((e) => {
			debugInfo("Local title model session could not be created", e);
			sessionPromise = null;
			return null;
		});
	}
	/**
	* Name a conversation from its first exchange.
	* @param {{userText: string, assistantText: string}} exchange
	* @returns {Promise<string|null>} a sanitized title, or null if unavailable
	*/
	async function generateChatTitle({ userText, assistantText }) {
		if (!userText) return null;
		if (!sessionPromise) return null;
		let session;
		try {
			session = await sessionPromise;
		} catch {
			return null;
		}
		if (!session) return null;
		let scratch = null;
		const controller = new AbortController();
		const timer = setTimeout(() => controller.abort(), GENERATE_TIMEOUT_MS);
		try {
			try {
				scratch = await session.clone({ signal: controller.signal });
			} catch (e) {
				debugInfo("Local title model clone unsupported, reusing session", e);
			}
			const prompt = `Question: ${clip(userText, MAX_USER_CHARS)}\nAnswer: ${clip(assistantText, MAX_ASSISTANT_CHARS)}`;
			const raw = await (scratch || session).prompt(prompt, {
				responseConstraint: TITLE_SCHEMA,
				signal: controller.signal
			});
			return sanitizeTitle(JSON.parse(raw)?.title);
		} catch (e) {
			debugInfo("Local title generation failed", e);
			return null;
		} finally {
			clearTimeout(timer);
			scratch?.destroy?.();
		}
	}
	/**
	* @param {string} text
	* @param {number} max
	* @returns {string}
	*/
	function clip(text, max) {
		const val = String(text || "").trim();
		return val.length > max ? `${val.slice(0, max)}…` : val;
	}
	/**
	* Small models like to wrap titles in quotes or tack on a period despite being
	* told not to.
	* @param {string} raw
	* @returns {string|null}
	*/
	function sanitizeTitle(raw) {
		const val = String(raw || "").replace(/\s+/g, " ").replace(/^["'“”‘’\s]+|["'“”‘’\s.]+$/g, "").trim();
		return val ? val.slice(0, MAX_TITLE_CHARS) : null;
	}
	//#endregion
	//#region src/MessageComposer.svelte
	var root_1$12 = /* @__PURE__ */ from_html(`<div class="uc-chat-send-error svelte-jdanaw" role="alert"> </div>`);
	var root_2$15 = /* @__PURE__ */ from_html(`<button type="button" title="Stop response" aria-label="Stop response" class="t-Button t-Button--noLabel t-Button--icon uc-chat-composer-btn svelte-jdanaw"><span aria-hidden="true" class="t-Icon fa fa-stop"></span></button>`);
	var root_3$10 = /* @__PURE__ */ from_html(`<button type="button" title="Send message" aria-label="Send message" class="t-Button t-Button--noLabel t-Button--icon t-Button--hot uc-chat-composer-btn svelte-jdanaw"><span aria-hidden="true" class="t-Icon fa fa-paper-plane"></span></button>`);
	var root$14 = /* @__PURE__ */ from_html(`<!> <div class="chat-input svelte-jdanaw"><textarea class="apex-item-textarea svelte-jdanaw" rows="1"></textarea> <!></div>`, 1);
	var $$css$16 = {
		hash: "svelte-jdanaw",
		code: ".uc-chat-send-error.svelte-jdanaw {color:var(--uc-chat-danger-color);font-size:0.75em;padding:var(--uc-chat-space-1) var(--uc-chat-space-3);}\n\n  /* Shared by user chat, channel chat and AI chat. The send button used to be\n     welded to the textarea (left corners squared off) while the textarea kept\n     APEX's own field radius on the other side, so the pair read as one broken\n     control. They are now two APEX controls with a gap, which is how a field\n     and its button sit everywhere else in an APEX page. */.chat-input.svelte-jdanaw {width:100%;padding:var(--uc-chat-space-2) var(--uc-chat-space-3);display:flex;align-items:flex-end;gap:var(--uc-chat-space-2);}.chat-input.svelte-jdanaw > button.uc-chat-composer-btn:where(.svelte-jdanaw) {flex:0 0 auto;}textarea.apex-item-textarea.svelte-jdanaw {width:100%;\n    /* The 4em of right padding was left over from an absolutely positioned\n       send button; the button has been a flex sibling for a while, so all it\n       did was keep the caret away from a third of the field. */padding:0.5em 0.6em;resize:none;overflow-y:auto;min-height:2.25em;max-height:10em;font-family:var(--uc-chat-font-base);}"
	};
	function MessageComposer($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css$16);
		let roomId = prop($$props, "roomId", 7, void 0), userIds = prop($$props, "userIds", 7, void 0), roomName = prop($$props, "roomName", 7, void 0), regionId = prop($$props, "regionId", 7, void 0), onSend = prop($$props, "onSend", 7, void 0), placeholder = prop($$props, "placeholder", 7, "Type your message..."), disabled = prop($$props, "disabled", 7, false), onStop = prop($$props, "onStop", 7, void 0);
		let chatState = onSend() ? null : getChatState();
		let message = /* @__PURE__ */ state("");
		let sendError = /* @__PURE__ */ state("");
		let sending = /* @__PURE__ */ state(false);
		let textarea = null;
		async function handleSubmit() {
			if (get(message).trim() === "" || get(sending) || disabled()) return;
			set(sendError, "");
			set(sending, true);
			try {
				if (onSend()) await onSend()(get(message));
				else if (roomId()?.startsWith("newChat-")) {
					const newRoomId = await createRoomAndSendMessage({
						messageText: get(message),
						userIds: userIds(),
						regionId: regionId()
					});
					debugInfo("Message sent", {
						newRoomId,
						message: get(message)
					});
					openChat(chatState, {
						roomId: newRoomId,
						userIds: userIds(),
						roomName: roomName()
					});
				} else {
					const res = await sendMessage({
						roomId: roomId(),
						messageText: get(message),
						regionId: regionId()
					});
					debugInfo("Message sent", {
						roomId: roomId(),
						message: get(message),
						res
					});
					triggerEvent(EVENT_MESSAGE_SENT, {
						roomId: roomId(),
						message: get(message),
						messageId: res?.messageId
					}, regionId());
				}
				set(message, "");
			} catch (e) {
				debugError("Failed to send message", e);
				set(sendError, "Failed to send message. Please try again.");
			} finally {
				set(sending, false);
			}
		}
		function setTextBoxHeight() {
			textarea.style.height = "auto";
			textarea.style.height = `calc(${textarea.scrollHeight}px + 1px)`;
		}
		function handleInput() {
			setTextBoxHeight();
		}
		function handleKeyDown(event) {
			if (event.key === "Enter" && !event.shiftKey) {
				event.preventDefault();
				handleSubmit();
				setTimeout(() => {
					setTextBoxHeight();
				}, 20);
			}
		}
		var $$exports = {
			get roomId() {
				return roomId();
			},
			set roomId($$value = void 0) {
				roomId($$value);
				flushSync();
			},
			get userIds() {
				return userIds();
			},
			set userIds($$value = void 0) {
				userIds($$value);
				flushSync();
			},
			get roomName() {
				return roomName();
			},
			set roomName($$value = void 0) {
				roomName($$value);
				flushSync();
			},
			get regionId() {
				return regionId();
			},
			set regionId($$value = void 0) {
				regionId($$value);
				flushSync();
			},
			get onSend() {
				return onSend();
			},
			set onSend($$value = void 0) {
				onSend($$value);
				flushSync();
			},
			get placeholder() {
				return placeholder();
			},
			set placeholder($$value = "Type your message...") {
				placeholder($$value);
				flushSync();
			},
			get disabled() {
				return disabled();
			},
			set disabled($$value = false) {
				disabled($$value);
				flushSync();
			},
			get onStop() {
				return onStop();
			},
			set onStop($$value = void 0) {
				onStop($$value);
				flushSync();
			}
		};
		var fragment = root$14();
		var node = first_child(fragment);
		var consequent = ($$anchor) => {
			var div = root_1$12();
			var text = child(div, true);
			reset(div);
			template_effect(() => set_text(text, get(sendError)));
			append($$anchor, div);
		};
		if_block(node, ($$render) => {
			if (get(sendError)) $$render(consequent);
		});
		var div_1 = sibling(node, 2);
		var textarea_1 = child(div_1);
		remove_textarea_child(textarea_1);
		bind_this(textarea_1, ($$value) => textarea = $$value, () => textarea);
		var node_1 = sibling(textarea_1, 2);
		var consequent_1 = ($$anchor) => {
			var button = root_2$15();
			delegated("click", button, function(...$$args) {
				onStop()?.apply(this, $$args);
			});
			append($$anchor, button);
		};
		var alternate = ($$anchor) => {
			var button_1 = root_3$10();
			template_effect(() => button_1.disabled = disabled() || get(sending));
			delegated("click", button_1, handleSubmit);
			append($$anchor, button_1);
		};
		if_block(node_1, ($$render) => {
			if (disabled() && onStop()) $$render(consequent_1);
			else $$render(alternate, -1);
		});
		reset(div_1);
		template_effect(() => set_attribute(textarea_1, "placeholder", placeholder()));
		delegated("input", textarea_1, handleInput);
		delegated("keydown", textarea_1, handleKeyDown);
		bind_value(textarea_1, () => get(message), ($$value) => set(message, $$value));
		append($$anchor, fragment);
		return pop($$exports);
	}
	delegate([
		"input",
		"keydown",
		"click"
	]);
	create_custom_element(MessageComposer, {
		roomId: {},
		userIds: {},
		roomName: {},
		regionId: {},
		onSend: {},
		placeholder: {},
		disabled: {},
		onStop: {}
	}, [], [], { mode: "open" });
	//#endregion
	//#region src/AiChatPane.svelte
	var root_1$11 = /* @__PURE__ */ from_html(`<button type="button" class="t-Button t-Button--small t-Button--noLabel t-Button--icon t-Button--simple" title="Debug info" aria-label="Debug info"><span aria-hidden="true" class="t-Icon fa fa-bug"></span></button>`);
	var root_2$14 = /* @__PURE__ */ from_html(`<button type="button" class="t-Button t-Button--small t-Button--noLabel t-Button--icon t-Button--simple" title="Close" aria-label="Close"><span aria-hidden="true" class="t-Icon fa fa-close"></span></button>`);
	var root$13 = /* @__PURE__ */ from_html(`<div class="uc-ai-chat-pane svelte-1gp8sdx"><div class="uc-visually-hidden svelte-1gp8sdx" aria-live="polite" aria-atomic="true"> </div> <div class="uc-ai-chat-header svelte-1gp8sdx"><div class="uc-ai-chat-header-left svelte-1gp8sdx"><h2 class="uc-ai-chat-title svelte-1gp8sdx"> </h2></div> <div class="uc-ai-chat-header-right svelte-1gp8sdx"><!> <button type="button" class="t-Button t-Button--small t-Button--simple uc-ai-new-chat svelte-1gp8sdx" title="New chat"><span aria-hidden="true" class="t-Icon fa fa-plus"></span> <span class="uc-ai-new-chat-label svelte-1gp8sdx">New chat</span></button> <!></div></div> <div class="uc-ai-chat-body svelte-1gp8sdx"><!></div> <!> <!> <div class="uc-ai-chat-footer svelte-1gp8sdx"><!></div> <!></div>`);
	var $$css$15 = {
		hash: "svelte-1gp8sdx",
		code: ".uc-ai-chat-pane.svelte-1gp8sdx {display:flex;flex-direction:column;height:100%;max-height:100%;\n    /* Floor height so an embedded region doesn't collapse to the composer.\n       Overridden by the inline min-height from the `minHeight` prop. */min-height:var(--uc-chat-ai-min-height, 25em);overflow:hidden;\n    /* The pane owns its surface so the translucent canvas tint below has\n       something predictable to composite over. */background-color:var(--uc-chat-surface-background-color);\n    /* Lets the header adapt to the region's own width rather than the viewport. */container-type:inline-size;container-name:uc-ai-pane;}.uc-visually-hidden.svelte-1gp8sdx {position:absolute;width:1px;height:1px;margin:-1px;padding:0;overflow:hidden;clip:rect(0 0 0 0);clip-path:inset(50%);white-space:nowrap;border:0;}\n\n  /* Header and footer are chrome: they sit on the plain surface and are divided\n     from the transcript by a hairline, the way an APEX region header is. The\n     old drop shadows smudged onto the canvas and read as a rendering artefact\n     rather than a boundary. */.uc-ai-chat-header.svelte-1gp8sdx {background-color:var(--uc-chat-surface-background-color);\n    /* Was a raw 48px in an em-only codebase, and 2px taller than the footer for\n       no reason. Both bars now derive from the same measure. */min-height:var(--uc-chat-ai-bar-height, 3em);border-bottom:1px solid var(--uc-chat-component-border-color);display:flex;align-items:center;justify-content:space-between;gap:var(--uc-chat-space-2);padding:var(--uc-chat-space-1) var(--uc-chat-space-3);flex:0 0 auto;z-index:1;}.uc-ai-chat-header-left.svelte-1gp8sdx {display:flex;align-items:center;gap:var(--uc-chat-space-2);\n    /* Let the title shrink instead of pushing the buttons off the header. */min-width:0;}.uc-ai-chat-header-right.svelte-1gp8sdx {display:flex;align-items:center;gap:var(--uc-chat-space-1);flex:0 0 auto;}.uc-ai-chat-title.svelte-1gp8sdx {margin:0;padding:0;font-weight:600;color:var(--uc-chat-component-text-title-color);\n    /* Region titles in the Universal Theme are barely larger than body text;\n       1.1em on top of a bold weight was pulling focus from the conversation. */font-size:1em;letter-spacing:0.01em;\n    /* Generated titles are free-form; keep them on one line. */overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}.uc-ai-new-chat.svelte-1gp8sdx {display:inline-flex;align-items:center;gap:var(--uc-chat-space-1);white-space:nowrap;}\n\n  /* Only genuinely narrow regions fall back to the icon alone; the button keeps\n     its tooltip and accessible name from the title attribute. */\n  @container uc-ai-pane (max-width: 22em) {.uc-ai-new-chat-label.svelte-1gp8sdx {display:none;}\n  }.uc-ai-chat-body.svelte-1gp8sdx {flex:1;min-height:0;overflow:hidden;\n    /* Translucent, so it composites over the pane's own surface into a faint\n       recess. The old value was --uc-chat-footer-background-color (#f2f2f2),\n       the very same grey the tool card painted its header with — which is why\n       the card looked like it had a hole punched in it. */background-color:var(--uc-chat-canvas-background-color);}.uc-ai-chat-footer.svelte-1gp8sdx {display:flex;flex-direction:column;justify-content:center;background-color:var(--uc-chat-surface-background-color);border-top:1px solid var(--uc-chat-component-border-color);flex:0 0 auto;z-index:1;\n    /* Was a fixed 50px, which clipped the composer as soon as the textarea grew\n       past one line (it is allowed to reach 10em). */min-height:var(--uc-chat-ai-bar-height, 3em);}"
	};
	function AiChatPane($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css$15);
		let regionId = prop($$props, "regionId", 7), agentCode = prop($$props, "agentCode", 7), agentVersion = prop($$props, "agentVersion", 7), sessionId = prop($$props, "sessionId", 7), showReasoning = prop($$props, "showReasoning", 7, false), showTools = prop($$props, "showTools", 7, false), showMetadata = prop($$props, "showMetadata", 7, false), showDebug = prop($$props, "showDebug", 7, false), suggestedPrompts = prop($$props, "suggestedPrompts", 7, ""), headerTitle = prop($$props, "headerTitle", 7, ""), avatarIcon = prop($$props, "avatarIcon", 7, ""), welcomeMessage = prop($$props, "welcomeMessage", 7, ""), minHeight = prop($$props, "minHeight", 7, ""), thinkingAnimation = prop($$props, "thinkingAnimation", 7, ""), thinkingDetail = prop($$props, "thinkingDetail", 7, ""), autoTitle = prop($$props, "autoTitle", 7, false), collectFeedback = prop($$props, "collectFeedback", 7, false), hideDialog = prop($$props, "hideDialog", 7);
		let aiState = createAiChatState({
			sessionId: sessionId() || null,
			agentCode: agentCode(),
			agentVersion: agentVersion()
		});
		let messageList = /* @__PURE__ */ state(void 0);
		let debugDialog = /* @__PURE__ */ state(void 0);
		let pollInterval = null;
		let currentTurnUserMessageId = null;
		let dismissedGuardrail = null;
		let liveText = /* @__PURE__ */ state("");
		let promptList = /* @__PURE__ */ user_derived(() => parseSuggestedPrompts(suggestedPrompts()));
		let title = /* @__PURE__ */ user_derived(() => headerTitle()?.trim() || "AI Assistant");
		let displayTitle = /* @__PURE__ */ user_derived(() => aiState.sessionTitle?.trim() || get(title));
		let animVariant = /* @__PURE__ */ user_derived(() => normalizeVariant(thinkingAnimation(), AI_ANIM_DOTS));
		let detailLevel = /* @__PURE__ */ user_derived(() => normalizeEnum(thinkingDetail(), AI_DETAIL_LEVELS, AI_DETAIL_TOOLS));
		let avatarIconClass = /* @__PURE__ */ user_derived(() => normalizeIconClass(avatarIcon()));
		function normalizeIconClass(raw) {
			let val = (raw || "").trim();
			if (!val) return "fa fa-robot";
			if (val.split(/\s+/).some((t) => /^fa[srlbd]?$/.test(t))) return val;
			return `fa ${val}`;
		}
		let minHeightStyle = /* @__PURE__ */ user_derived(() => {
			let val = (minHeight() || "").trim();
			if (!val) return "";
			return `min-height: ${/^\d+$/.test(val) ? `${val}px` : val};`;
		});
		const POLL_INTERVAL_MS = 2e3;
		const POLL_TIMEOUT_MS = 6e5;
		const MAX_POLL_ERRORS = 3;
		function parseSuggestedPrompts(raw) {
			if (!raw) return [];
			if (Array.isArray(raw)) return raw.map((p) => String(p).trim()).filter(Boolean).slice(0, 6);
			let str = String(raw).trim();
			if (str === "") return [];
			if (str.startsWith("[")) try {
				let arr = JSON.parse(str);
				return Array.isArray(arr) ? arr.map((p) => String(p).trim()).filter(Boolean).slice(0, 6) : [];
			} catch {
				return [];
			}
			return str.split(",").map((s) => s.trim()).filter(Boolean).slice(0, 6);
		}
		user_effect(() => {
			if (!autoTitle()) return;
			probeTitleModel();
		});
		async function maybeGenerateTitle() {
			if (!autoTitle() || aiState.sessionTitle) return;
			let sessionId = aiState.sessionId;
			if (!sessionId) return;
			let exchange = get(messageList)?.getFirstExchange();
			if (!exchange?.userText || !exchange.assistantText) return;
			let generated = await generateChatTitle(exchange);
			if (!generated) return;
			if (aiState.sessionId !== sessionId) return;
			try {
				aiState.sessionTitle = (await aiSetTitle({
					sessionId,
					title: generated,
					regionId: regionId()
				}))?.sessionTitle || generated;
			} catch (e) {
				debugError("Storing the conversation title failed", e);
			}
		}
		async function handleFeedback({ rating, comment }) {
			let sessionId = aiState.sessionId;
			if (!sessionId) return;
			let previous = aiState.feedback;
			aiState.feedback = rating ? {
				rating,
				comment: comment || void 0
			} : null;
			try {
				let res = await aiSetFeedback({
					sessionId,
					rating,
					comment,
					regionId: regionId()
				});
				if (aiState.sessionId !== sessionId) return;
				aiState.feedback = res?.feedbackRating ? {
					rating: res.feedbackRating,
					comment: res.feedbackComment
				} : null;
			} catch (e) {
				debugError("Storing the conversation feedback failed", e);
				if (aiState.sessionId === sessionId) aiState.feedback = previous;
			}
		}
		function stopPolling() {
			if (pollInterval) {
				clearInterval(pollInterval);
				pollInterval = null;
			}
		}
		async function announce(text) {
			if (!text) return;
			set(liveText, "");
			await tick();
			set(liveText, text, true);
		}
		function markdownToText(md) {
			if (!md) return "";
			let el = document.createElement("div");
			el.innerHTML = renderMarkdown(md);
			return el.textContent || "";
		}
		function applyGuardrail(guardrail, { silent = false } = {}) {
			if (!guardrail) return;
			let key = `${guardrail.state}:${guardrail.kind}`;
			if (dismissedGuardrail === key) return;
			dismissedGuardrail = null;
			aiState.guardrail = guardrail;
			if (!silent && guardrail.state === "hit") announce(guardrailMessage(guardrail.state, guardrail.kind));
		}
		function dismissGuardrail() {
			let g = aiState.guardrail;
			dismissedGuardrail = g ? `${g.state}:${g.kind}` : null;
			aiState.guardrail = null;
		}
		function dismissContextConflict() {
			aiState.contextConflict = false;
		}
		function appendAssistantNotice(content) {
			get(messageList)?.appendMessages([{
				messageId: `notice-${Date.now()}`,
				role: "assistant",
				content,
				messageDate: (/* @__PURE__ */ new Date()).toISOString()
			}]);
			announce(content);
		}
		function endTurn(noticeContent) {
			stopPolling();
			aiState.isProcessing = false;
			currentTurnUserMessageId = null;
			if (noticeContent) appendAssistantNotice(noticeContent);
		}
		function startPolling(userMessageId) {
			stopPolling();
			let startTime = Date.now();
			let consecutiveErrors = 0;
			pollInterval = setInterval(async () => {
				if (Date.now() - startTime > POLL_TIMEOUT_MS) {
					endTurn("The AI is taking too long to respond. Please try again.");
					return;
				}
				try {
					let res = await aiGetMessages({
						sessionId: aiState.sessionId,
						lastMessageId: userMessageId,
						olderOrNewer: "newer",
						regionId: regionId()
					});
					consecutiveErrors = 0;
					let status = res.turn?.status;
					let messages = res.messages || [];
					if (res.sessionTitle) aiState.sessionTitle = res.sessionTitle;
					if (res.feedback) aiState.feedback = res.feedback;
					applyGuardrail(res.guardrail);
					if (status === "error") {
						let grKind = res.turn?.guardrail;
						let content = grKind ? guardrailMessage("hit", grKind) : res.turn?.contextConflict ? AI_CONTEXT_CONFLICT_MESSAGE : res.turn?.errorDetail;
						for (let m of messages) if (m.role === "assistant") {
							m.isError = true;
							if (content) m.content = content;
						}
					}
					if (messages.length > 0) get(messageList)?.appendMessages(messages);
					if (status === "done") {
						get(messageList)?.removeRunningPlaceholders();
						endTurn();
						let lastAssistant = [...messages].reverse().find((m) => m.role === "assistant");
						if (lastAssistant) announce(markdownToText(lastAssistant.content));
						maybeGenerateTitle().catch((e) => debugError("Conversation title generation failed", e));
					} else if (status === "error") {
						get(messageList)?.removeRunningPlaceholders();
						let errRow = [...messages].reverse().find((m) => m.role === "assistant");
						endTurn();
						let grKind = res.turn?.guardrail;
						if (res.turn?.contextConflict) aiState.contextConflict = true;
						if (errRow) announce(markdownToText(errRow.content));
						else if (grKind) appendAssistantNotice(guardrailMessage("hit", grKind));
						else if (res.turn?.contextConflict) appendAssistantNotice(AI_CONTEXT_CONFLICT_MESSAGE);
						else appendAssistantNotice(res.turn?.errorDetail || "The AI request failed. Please try again.");
						if (grKind) applyGuardrail({
							state: "hit",
							kind: grKind
						}, { silent: true });
					} else if (status === "cancelled") {
						get(messageList)?.removeRunningPlaceholders();
						endTurn("Response stopped.");
					} else if (status == null) {
						if (messages.some((m) => m.role === "assistant")) endTurn();
					}
				} catch (e) {
					consecutiveErrors++;
					debugError(`Polling failed (${consecutiveErrors}/${MAX_POLL_ERRORS})`, e);
					if (consecutiveErrors >= MAX_POLL_ERRORS) endTurn("Lost connection while waiting for the AI response. Please try again.");
				}
			}, POLL_INTERVAL_MS);
		}
		onDestroy(() => {
			stopPolling();
		});
		async function ensureSession() {
			if (aiState.sessionId) return;
			let res = await aiNewSession({
				agentCode: aiState.agentCode,
				agentVersion: aiState.agentVersion,
				regionId: regionId()
			});
			get(messageList)?.adoptNewSession(res.sessionId);
			aiState.sessionId = res.sessionId;
			debugInfo("AI session created", { sessionId: aiState.sessionId });
		}
		async function handleSend(messageText) {
			if (!messageText.trim() || aiState.isProcessing) return;
			if (autoTitle()) warmUpTitleModel();
			aiState.isProcessing = true;
			let tempId = `temp-user-${Date.now()}`;
			try {
				await ensureSession();
				get(messageList)?.appendMessages([{
					messageId: tempId,
					role: "user",
					content: messageText,
					messageDate: (/* @__PURE__ */ new Date()).toISOString()
				}], { forceScroll: true });
				let res = await aiSendMessage({
					sessionId: aiState.sessionId,
					messageText,
					agentCode: aiState.agentCode,
					agentVersion: aiState.agentVersion,
					regionId: regionId()
				});
				if (res.contextConflict) {
					aiState.contextConflict = true;
					announce(AI_CONTEXT_CONFLICT_MESSAGE);
					endTurn();
					return;
				}
				if (res.sessionReset) {
					get(messageList)?.adoptNewSession(res.sessionId);
					aiState.sessionId = res.sessionId;
					aiState.sessionTitle = null;
					aiState.feedback = null;
					aiState.contextConflict = false;
					get(messageList)?.appendMessages([{
						messageId: res.userMessageId,
						role: "user",
						content: messageText,
						messageDate: (/* @__PURE__ */ new Date()).toISOString()
					}], { forceScroll: true });
					debugInfo("AI session re-bound to a new run context", { sessionId: res.sessionId });
				} else {
					get(messageList)?.confirmMessage(tempId, res.userMessageId);
					aiState.contextConflict = false;
				}
				applyGuardrail(res.guardrail);
				if (!aiState.isProcessing) {
					aiCancel({
						sessionId: aiState.sessionId,
						userMessageId: res.userMessageId,
						regionId: regionId()
					}).catch((e) => debugError("AI cancel of stopped send failed", e));
					return;
				}
				currentTurnUserMessageId = res.userMessageId;
				debugInfo("AI message submitted, polling for response", { userMessageId: res.userMessageId });
				startPolling(res.userMessageId);
			} catch (e) {
				debugError("AI send failed", e);
				endTurn("Sorry, something went wrong. Please try again.");
			}
		}
		async function handleStop() {
			let userMsgId = currentTurnUserMessageId;
			endTurn("Response stopped.");
			if (!userMsgId) return;
			try {
				await aiCancel({
					sessionId: aiState.sessionId,
					userMessageId: userMsgId,
					regionId: regionId()
				});
			} catch (e) {
				debugError("AI cancel failed", e);
			}
		}
		function handleNewConversation() {
			if (!get(messageList)?.hasMessages()) {
				startNewConversation();
				return;
			}
			let question = "Start a new conversation? The current one will be cleared.";
			if (typeof apex?.message?.confirm === "function") {
				apex.message.confirm(question, (ok) => {
					if (ok) startNewConversation();
				});
				return;
			}
			if (window.confirm(question)) startNewConversation();
		}
		async function startNewConversation() {
			let res;
			try {
				res = await aiNewSession({
					agentCode: aiState.agentCode,
					agentVersion: aiState.agentVersion,
					regionId: regionId()
				});
			} catch (e) {
				debugError("Failed to start a new conversation", e);
				appendAssistantNotice("Could not start a new conversation. Please try again.");
				return;
			}
			if (aiState.isProcessing && currentTurnUserMessageId) aiCancel({
				sessionId: aiState.sessionId,
				userMessageId: currentTurnUserMessageId,
				regionId: regionId()
			}).catch((e) => debugError("AI cancel on new conversation failed", e));
			stopPolling();
			aiState.isProcessing = false;
			currentTurnUserMessageId = null;
			aiState.sessionTitle = null;
			aiState.feedback = null;
			aiState.contextConflict = false;
			get(messageList)?.adoptNewSession(res.sessionId);
			aiState.sessionId = res.sessionId;
			debugInfo("New AI session created", { sessionId: aiState.sessionId });
		}
		var $$exports = {
			get regionId() {
				return regionId();
			},
			set regionId($$value) {
				regionId($$value);
				flushSync();
			},
			get agentCode() {
				return agentCode();
			},
			set agentCode($$value) {
				agentCode($$value);
				flushSync();
			},
			get agentVersion() {
				return agentVersion();
			},
			set agentVersion($$value) {
				agentVersion($$value);
				flushSync();
			},
			get sessionId() {
				return sessionId();
			},
			set sessionId($$value) {
				sessionId($$value);
				flushSync();
			},
			get showReasoning() {
				return showReasoning();
			},
			set showReasoning($$value = false) {
				showReasoning($$value);
				flushSync();
			},
			get showTools() {
				return showTools();
			},
			set showTools($$value = false) {
				showTools($$value);
				flushSync();
			},
			get showMetadata() {
				return showMetadata();
			},
			set showMetadata($$value = false) {
				showMetadata($$value);
				flushSync();
			},
			get showDebug() {
				return showDebug();
			},
			set showDebug($$value = false) {
				showDebug($$value);
				flushSync();
			},
			get suggestedPrompts() {
				return suggestedPrompts();
			},
			set suggestedPrompts($$value = "") {
				suggestedPrompts($$value);
				flushSync();
			},
			get headerTitle() {
				return headerTitle();
			},
			set headerTitle($$value = "") {
				headerTitle($$value);
				flushSync();
			},
			get avatarIcon() {
				return avatarIcon();
			},
			set avatarIcon($$value = "") {
				avatarIcon($$value);
				flushSync();
			},
			get welcomeMessage() {
				return welcomeMessage();
			},
			set welcomeMessage($$value = "") {
				welcomeMessage($$value);
				flushSync();
			},
			get minHeight() {
				return minHeight();
			},
			set minHeight($$value = "") {
				minHeight($$value);
				flushSync();
			},
			get thinkingAnimation() {
				return thinkingAnimation();
			},
			set thinkingAnimation($$value = "") {
				thinkingAnimation($$value);
				flushSync();
			},
			get thinkingDetail() {
				return thinkingDetail();
			},
			set thinkingDetail($$value = "") {
				thinkingDetail($$value);
				flushSync();
			},
			get autoTitle() {
				return autoTitle();
			},
			set autoTitle($$value = false) {
				autoTitle($$value);
				flushSync();
			},
			get collectFeedback() {
				return collectFeedback();
			},
			set collectFeedback($$value = false) {
				collectFeedback($$value);
				flushSync();
			},
			get hideDialog() {
				return hideDialog();
			},
			set hideDialog($$value) {
				hideDialog($$value);
				flushSync();
			}
		};
		var div = root$13();
		var div_1 = child(div);
		var text_1 = child(div_1, true);
		reset(div_1);
		var div_2 = sibling(div_1, 2);
		var div_3 = child(div_2);
		var h2 = child(div_3);
		var text_2 = child(h2, true);
		reset(h2);
		reset(div_3);
		var div_4 = sibling(div_3, 2);
		var node = child(div_4);
		var consequent = ($$anchor) => {
			var button = root_1$11();
			delegated("click", button, () => get(debugDialog)?.open());
			append($$anchor, button);
		};
		if_block(node, ($$render) => {
			if (showDebug()) $$render(consequent);
		});
		var button_1 = sibling(node, 2);
		var node_1 = sibling(button_1, 2);
		var consequent_1 = ($$anchor) => {
			var button_2 = root_2$14();
			delegated("click", button_2, function(...$$args) {
				hideDialog()?.apply(this, $$args);
			});
			append($$anchor, button_2);
		};
		if_block(node_1, ($$render) => {
			if (hideDialog()) $$render(consequent_1);
		});
		reset(div_4);
		reset(div_2);
		var div_5 = sibling(div_2, 2);
		bind_this(AiMessageList(child(div_5), {
			get regionId() {
				return regionId();
			},
			get showReasoning() {
				return showReasoning();
			},
			get showTools() {
				return showTools();
			},
			get showMetadata() {
				return showMetadata();
			},
			get avatarIcon() {
				return get(avatarIconClass);
			},
			get suggestedPrompts() {
				return get(promptList);
			},
			onPromptClick: handleSend,
			get welcomeMessage() {
				return welcomeMessage();
			},
			get thinkingAnimation() {
				return get(animVariant);
			},
			get thinkingDetail() {
				return get(detailLevel);
			},
			onGuardrail: applyGuardrail,
			get collectFeedback() {
				return collectFeedback();
			},
			onFeedback: handleFeedback
		}), ($$value) => set(messageList, $$value, true), () => get(messageList));
		reset(div_5);
		var node_3 = sibling(div_5, 2);
		var consequent_2 = ($$anchor) => {
			AiGuardrailBanner($$anchor, {
				get state() {
					return aiState.guardrail.state;
				},
				get kind() {
					return aiState.guardrail.kind;
				},
				onDismiss: dismissGuardrail
			});
		};
		if_block(node_3, ($$render) => {
			if (aiState.guardrail) $$render(consequent_2);
		});
		var node_4 = sibling(node_3, 2);
		var consequent_3 = ($$anchor) => {
			AiGuardrailBanner($$anchor, {
				get state() {
					return "hit";
				},
				get text() {
					return AI_CONTEXT_CONFLICT_MESSAGE;
				},
				onDismiss: dismissContextConflict
			});
		};
		if_block(node_4, ($$render) => {
			if (aiState.contextConflict) $$render(consequent_3);
		});
		var div_6 = sibling(node_4, 2);
		MessageComposer(child(div_6), {
			onSend: handleSend,
			placeholder: "Ask the AI...",
			get disabled() {
				return aiState.isProcessing;
			},
			onStop: handleStop
		});
		reset(div_6);
		var node_6 = sibling(div_6, 2);
		var consequent_4 = ($$anchor) => {
			bind_this(AiDebugDialog($$anchor, {
				get regionId() {
					return regionId();
				},
				get sessionId() {
					return aiState.sessionId;
				},
				get agentCode() {
					return aiState.agentCode;
				},
				get agentVersion() {
					return aiState.agentVersion;
				}
			}), ($$value) => set(debugDialog, $$value, true), () => get(debugDialog));
		};
		if_block(node_6, ($$render) => {
			if (showDebug()) $$render(consequent_4);
		});
		reset(div);
		template_effect(() => {
			set_style(div, get(minHeightStyle));
			set_text(text_1, get(liveText));
			set_attribute(h2, "title", get(displayTitle));
			set_text(text_2, get(displayTitle));
		});
		delegated("click", button_1, handleNewConversation);
		append($$anchor, div);
		return pop($$exports);
	}
	delegate(["click"]);
	create_custom_element(AiChatPane, {
		regionId: {},
		agentCode: {},
		agentVersion: {},
		sessionId: {},
		showReasoning: {},
		showTools: {},
		showMetadata: {},
		showDebug: {},
		suggestedPrompts: {},
		headerTitle: {},
		avatarIcon: {},
		welcomeMessage: {},
		minHeight: {},
		thinkingAnimation: {},
		thinkingDetail: {},
		autoTitle: {},
		collectFeedback: {},
		hideDialog: {}
	}, [], [], { mode: "open" });
	//#endregion
	//#region src/ChannelList.svelte
	var root_3$9 = /* @__PURE__ */ from_html(`<span aria-hidden="true" class="fa fa-lock"></span>`);
	var root_4$4 = /* @__PURE__ */ from_html(`<span aria-hidden="true" class="fa fa-smile-o"></span>`);
	var root_5$4 = /* @__PURE__ */ from_html(`<span aria-hidden="true" class="fa fa-hashtag"></span>`);
	var root_6$3 = /* @__PURE__ */ from_html(`<span class="uc-channel-thread-dot svelte-1g3qloq" aria-label="new thread replies"></span>`);
	var root_7$1 = /* @__PURE__ */ from_html(`<div class="uc-channel-badge svelte-1g3qloq"> </div>`);
	var root_2$13 = /* @__PURE__ */ from_html(`<li class="uc-channel-li svelte-1g3qloq"><button type="button" class="uc-channel-button svelte-1g3qloq"><div><div class="uc-channel-icon svelte-1g3qloq"><!></div> <div class="uc-channel-info svelte-1g3qloq"><span class="uc-channel-name svelte-1g3qloq"> </span></div> <!> <!></div></button></li>`);
	var root$12 = /* @__PURE__ */ from_html(`<div class="uc-channel-list-header svelte-1g3qloq"><h3 class="uc-channel-list-title svelte-1g3qloq">Channels</h3></div> <ul class="uc-channel-ul svelte-1g3qloq"><!> <!></ul>`, 1);
	var $$css$14 = {
		hash: "svelte-1g3qloq",
		code: "\n	/* Same bar as the transcript header opposite it, so the two halves of the\n	   region line up instead of missing each other by a few pixels. */.uc-channel-list-header.svelte-1g3qloq {display:flex;align-items:center;min-height:var(--uc-chat-bar-height);padding:var(--uc-chat-space-1) var(--uc-chat-space-3);border-bottom:1px solid var(--uc-chat-component-border-color);background-color:var(--uc-chat-surface-background-color);flex:0 0 auto;}.uc-channel-list-title.svelte-1g3qloq {margin:0;font-size:1em;font-weight:600;letter-spacing:0.01em;color:var(--uc-chat-component-text-title-color);}.uc-channel-ul.svelte-1g3qloq {margin:0;padding:0;list-style:none;}.uc-channel-li.svelte-1g3qloq {list-style:none;}.uc-channel-button.svelte-1g3qloq {width:100%;background:none;border:none;padding:0;margin:0;cursor:pointer;text-align:left;font:inherit;color:inherit;}\n\n	/* A stripped-down button still needs a focus ring, and it belongs inside the\n	   full-bleed row rather than around it. */.uc-channel-button.svelte-1g3qloq:focus-visible {outline:none;}.uc-channel-button.svelte-1g3qloq:focus-visible .uc-channel-item:where(.svelte-1g3qloq) {outline:2px solid var(--uc-chat-accent-color);outline-offset:-2px;}.uc-channel-item.svelte-1g3qloq {padding:var(--uc-chat-space-2) var(--uc-chat-space-3);display:flex;align-items:center;gap:var(--uc-chat-space-2);\n		/* The selected row is marked by a rail plus a tint: the rail alone is\n		   invisible when scanning, the 2.5% tint alone is too quiet to find. The\n		   colour is the app's own primary, not the fixed blue --u-color-31 that\n		   used to make every app's channel list blue whatever its theme. */border-left:0.1875em solid transparent;\n		/* 0.5px is not a length a display can draw — it rounded to 0 or 1 device\n		   pixel depending on the pixel ratio, so rows disagreed about whether they\n		   had a divider. Rules between rows inside one pane are divisions, not\n		   edges, hence the inner-border token. */border-bottom:1px solid var(--uc-chat-component-inner-border-color);}.uc-channel-item.svelte-1g3qloq:hover {background-color:var(--uc-chat-hover-background-color);}.uc-channel-item-active.svelte-1g3qloq {border-left-color:var(--uc-chat-accent-color);background-color:var(--uc-chat-hover-background-color);}.uc-channel-icon.svelte-1g3qloq {font-size:0.9em;color:var(--uc-chat-component-text-muted-color);width:1.2em;text-align:center;flex-shrink:0;}.uc-channel-info.svelte-1g3qloq {flex:1;min-width:0;}.uc-channel-name.svelte-1g3qloq {font-weight:500;font-size:0.9em;color:var(--uc-chat-component-text-title-color);}.uc-channel-item-active.svelte-1g3qloq .uc-channel-name:where(.svelte-1g3qloq) {font-weight:600;}\n\n	/* Unread signals: the app's primary, because \"you have not read this\" is not\n	   an error. They were --uc-chat-color-9 (a fixed red, so every theme got the\n	   same alarm-red pill) and --uc-chat-color-31 (a fixed blue). */.uc-channel-thread-dot.svelte-1g3qloq {display:inline-block;width:0.5em;height:0.5em;border-radius:var(--uc-chat-radius-pill);background-color:var(--uc-chat-accent-color);flex-shrink:0;}.uc-channel-badge.svelte-1g3qloq {background-color:var(--uc-chat-accent-color);\n		/* The theme guarantees this pair is legible; the hardcoded #fff it\n		   replaces did not, and would have failed on a light accent. */color:var(--uc-chat-accent-contrast-color);font-size:0.7em;font-weight:600;line-height:1;padding:0.3em 0.45em;border-radius:var(--uc-chat-radius-pill);min-width:1.6em;text-align:center;flex-shrink:0;}"
	};
	function ChannelList($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css$14);
		const regionId = prop($$props, "regionId", 7);
		const channelState = getChannelState();
		let loading = /* @__PURE__ */ state(true);
		onMount(async () => {
			debugTrace("ChannelList onMount");
			const { channels } = await fetchChannels({ regionId: regionId() });
			set(loading, false);
			channelState.channels = channels;
			const channelRooms = channels.map((c) => `UC-APEX-CHAT-CH-${c.channelId}`);
			if (channelRooms.length > 0) joinAmsRooms(channelRooms);
		});
		function onClick(channel) {
			openChannel(channelState, channel);
		}
		var $$exports = {
			get regionId() {
				return regionId();
			},
			set regionId($$value) {
				regionId($$value);
				flushSync();
			}
		};
		var fragment = root$12();
		var ul = sibling(first_child(fragment), 2);
		var node = child(ul);
		var consequent = ($$anchor) => {
			Spinner($$anchor, {});
		};
		if_block(node, ($$render) => {
			if (get(loading)) $$render(consequent);
		});
		each(sibling(node, 2), 17, () => channelState.channels, index, ($$anchor, channel) => {
			var li = root_2$13();
			var button = child(li);
			var div = child(button);
			let classes;
			var div_1 = child(div);
			var node_2 = child(div_1);
			var consequent_1 = ($$anchor) => {
				append($$anchor, root_3$9());
			};
			var consequent_2 = ($$anchor) => {
				append($$anchor, root_4$4());
			};
			var alternate = ($$anchor) => {
				append($$anchor, root_5$4());
			};
			if_block(node_2, ($$render) => {
				if (!get(channel).canWrite && !get(channel).canReact) $$render(consequent_1);
				else if (!get(channel).canWrite && get(channel).canReact) $$render(consequent_2, 1);
				else $$render(alternate, -1);
			});
			reset(div_1);
			var div_2 = sibling(div_1, 2);
			var span_3 = child(div_2);
			var text = child(span_3, true);
			reset(span_3);
			reset(div_2);
			var node_3 = sibling(div_2, 2);
			var consequent_3 = ($$anchor) => {
				append($$anchor, root_6$3());
			};
			if_block(node_3, ($$render) => {
				if (get(channel).hasNewThreadReplies && !get(channel).unreadCount) $$render(consequent_3);
			});
			var node_4 = sibling(node_3, 2);
			var consequent_4 = ($$anchor) => {
				var div_3 = root_7$1();
				var text_1 = child(div_3, true);
				reset(div_3);
				template_effect(() => {
					set_attribute(div_3, "aria-label", `${get(channel).unreadCount ?? ""} unread messages`);
					set_text(text_1, get(channel).unreadCount > 99 ? "99+" : get(channel).unreadCount);
				});
				append($$anchor, div_3);
			};
			if_block(node_4, ($$render) => {
				if (get(channel).unreadCount > 0) $$render(consequent_4);
			});
			reset(div);
			reset(button);
			reset(li);
			template_effect(() => {
				set_attribute(button, "data-id", get(channel).channelId);
				set_attribute(button, "aria-current", channelState.currentChannel?.channelId === get(channel).channelId ? "true" : void 0);
				classes = set_class(div, 1, "uc-channel-item svelte-1g3qloq", null, classes, { "uc-channel-item-active": channelState.currentChannel?.channelId === get(channel).channelId });
				set_text(text, get(channel).channelName);
			});
			delegated("click", button, () => onClick(get(channel)));
			append($$anchor, li);
		});
		reset(ul);
		append($$anchor, fragment);
		return pop($$exports);
	}
	delegate(["click"]);
	create_custom_element(ChannelList, { regionId: {} }, [], [], { mode: "open" });
	//#endregion
	//#region src/Avatar.svelte
	var root_1$10 = /* @__PURE__ */ from_html(`<img class="uc-chat-avatar-img svelte-wu7i62" alt=""/>`);
	var root_2$12 = /* @__PURE__ */ from_html(`<div aria-hidden="true"><span> </span></div>`);
	var $$css$13 = {
		hash: "svelte-wu7i62",
		code: "\n  /* Identity colours, not theme accents: the u-color-N classes below are the\n     Universal Theme's own identity palette (the same swatches APEX uses for\n     calendars and cards), so they stay distinguishable from each other, ship a\n     matching foreground colour, and are supplied by the theme rather than\n     hardcoded here. They are deliberately NOT moved onto --uc-chat-accent-*:\n     one accent for fifteen people would defeat the point of the tile. */.uc-chat-avatar-img.svelte-wu7i62 {object-fit:cover;width:100%;height:100%;\n    /* Something to sit on while a remote image loads or 404s. */background-color:var(--uc-chat-inset-background-color);}.uc-chat-initials.svelte-wu7i62 {display:flex;\n    /* Derived from the tile the mount point asked for, so the glyph can never\n       drift out of proportion with it. This used to be a flat 1.2em that three\n       different components then reached in and overrode with :global(). */font-size:calc(var(--uc-chat-avatar-size, 2em) * 0.4);font-weight:600;letter-spacing:0.02em;align-items:center;justify-content:center;height:100%;user-select:none;}"
	};
	function Avatar($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css$13);
		let img = prop($$props, "img", 7), name = prop($$props, "name", 7);
		function getInitials(name) {
			if (!name) return "";
			const initials = name.split(" ").map((n) => n[0]);
			return initials.length > 1 ? initials.slice(0, 2).join("") : initials[0];
		}
		function getColorNumber(name) {
			if (!name) return 1;
			return name.split("").reduce((acc, char) => acc + char.charCodeAt(0), 0) % 15 + 1;
		}
		var $$exports = {
			get img() {
				return img();
			},
			set img($$value) {
				img($$value);
				flushSync();
			},
			get name() {
				return name();
			},
			set name($$value) {
				name($$value);
				flushSync();
			}
		};
		var fragment = comment();
		var node = first_child(fragment);
		var consequent = ($$anchor) => {
			var img_1 = root_1$10();
			template_effect(() => set_attribute(img_1, "src", img()));
			append($$anchor, img_1);
		};
		var alternate = ($$anchor) => {
			var div = root_2$12();
			var span = child(div);
			var text = child(span, true);
			reset(span);
			reset(div);
			template_effect(($0, $1) => {
				set_class(div, 1, $0, "svelte-wu7i62");
				set_text(text, $1);
			}, [() => `uc-chat-initials u-color-${getColorNumber(name())}`, () => getInitials(name())]);
			append($$anchor, div);
		};
		if_block(node, ($$render) => {
			if (img()) $$render(consequent);
			else $$render(alternate, -1);
		});
		append($$anchor, fragment);
		return pop($$exports);
	}
	create_custom_element(Avatar, {
		img: {},
		name: {}
	}, [], [], { mode: "open" });
	//#endregion
	//#region src/lib/VirtualList.svelte
	var root_1$9 = /* @__PURE__ */ from_html(`<svelte-virtual-list-row><!></svelte-virtual-list-row>`, 2);
	var root$11 = /* @__PURE__ */ from_html(`<svelte-virtual-list-viewport><svelte-virtual-list-contents></svelte-virtual-list-contents></svelte-virtual-list-viewport>`, 2);
	var $$css$12 = {
		hash: "svelte-16nckvm",
		code: "svelte-virtual-list-viewport.svelte-16nckvm {position:relative;overflow-y:auto;-webkit-overflow-scrolling:touch;display:block;}svelte-virtual-list-contents.svelte-16nckvm,\n  svelte-virtual-list-row.svelte-16nckvm {display:block;}svelte-virtual-list-row.svelte-16nckvm {overflow:hidden;}"
	};
	function VirtualList($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css$12);
		const items = prop($$props, "items", 7), height = prop($$props, "height", 7), itemHeight = prop($$props, "itemHeight", 7), children = prop($$props, "Children", 7), onScrollEnd = prop($$props, "onScrollEnd", 7), onScrollTop = prop($$props, "onScrollTop", 7);
		let start = /* @__PURE__ */ state(0);
		let end = /* @__PURE__ */ state(0);
		let height_map = /* @__PURE__ */ state(proxy([]));
		let rows = /* @__PURE__ */ state(null);
		let viewport = /* @__PURE__ */ state(null);
		let contents = /* @__PURE__ */ state(null);
		let viewport_height = /* @__PURE__ */ state(0);
		let mounted = /* @__PURE__ */ state(false);
		let top = /* @__PURE__ */ state(0);
		let bottom = /* @__PURE__ */ state(0);
		let average_height = /* @__PURE__ */ state(null);
		const visible = /* @__PURE__ */ user_derived(() => items().slice(get(start), get(end)).map((data, i) => {
			return {
				index: i + get(start),
				data
			};
		}));
		user_effect(() => {
			if (get(mounted)) refresh(items(), get(viewport_height), itemHeight());
		});
		let throttleEndTimeout = null;
		let throttleTopTimeout = null;
		function throttleOnScrollEnd() {
			if (!onScrollEnd()) return;
			if (throttleEndTimeout !== null) return;
			onScrollEnd()();
			throttleEndTimeout = setTimeout(() => {
				throttleEndTimeout = null;
			}, 1e3);
		}
		function throttleOnScrollTop() {
			if (!onScrollTop()) return;
			if (throttleTopTimeout !== null) return;
			onScrollTop()();
			throttleTopTimeout = setTimeout(() => {
				throttleTopTimeout = null;
			}, 1e3);
		}
		async function refresh(items, viewport_height, itemHeight) {
			const { scrollTop } = get(viewport);
			await tick();
			let content_height = get(top) - scrollTop;
			let i = get(start);
			while (content_height < viewport_height && i < items.length) {
				let row = get(rows)[i - get(start)];
				if (!row) {
					set(end, i + 1);
					await tick();
					row = get(rows)[i - get(start)];
				}
				const row_height = get(height_map)[i] = itemHeight || row.offsetHeight;
				content_height += row_height;
				i += 1;
			}
			set(end, i, true);
			const remaining = items.length - get(end);
			set(average_height, (get(top) + content_height) / get(end));
			if (get(end) === 0) set(average_height, 0);
			set(bottom, remaining * get(average_height));
			get(height_map).length = items.length;
			if (get(start) >= items.length) get(viewport).scrollTo(0, 0);
		}
		async function handle_scroll() {
			const { scrollTop } = get(viewport);
			const old_start = get(start);
			for (let v = 0; v < get(rows).length; v += 1) get(height_map)[get(start) + v] = itemHeight() || get(rows)[v].offsetHeight;
			let i = 0;
			let y = 0;
			while (i < items().length) {
				const row_height = get(height_map)[i] || get(average_height);
				if (y + row_height > scrollTop) {
					set(start, i, true);
					set(top, y, true);
					break;
				}
				y += row_height;
				i += 1;
			}
			while (i < items().length) {
				y += get(height_map)[i] || get(average_height);
				i += 1;
				if (y > scrollTop + get(viewport_height)) break;
			}
			set(end, i, true);
			const remaining = items().length - get(end);
			set(average_height, y / get(end));
			while (i < items().length) get(height_map)[i++] = get(average_height);
			set(bottom, remaining * get(average_height));
			if (get(start) < old_start) {
				await tick();
				let expected_height = 0;
				let actual_height = 0;
				for (let i = get(start); i < old_start; i += 1) if (get(rows)[i - get(start)]) {
					expected_height += get(height_map)[i];
					actual_height += itemHeight() || get(rows)[i - get(start)].offsetHeight;
				}
				const d = actual_height - expected_height;
				get(viewport).scrollTo(0, scrollTop + d);
			}
			if (scrollTop === 0 && items().length > 0) throttleOnScrollTop();
			if (get(bottom) / (get(average_height) * items().length) * 100 < 20) throttleOnScrollEnd();
		}
		onMount(() => {
			set(rows, get(contents).getElementsByTagName("svelte-virtual-list-row"), true);
			set(mounted, true);
		});
		var $$exports = {
			get items() {
				return items();
			},
			set items($$value) {
				items($$value);
				flushSync();
			},
			get height() {
				return height();
			},
			set height($$value) {
				height($$value);
				flushSync();
			},
			get itemHeight() {
				return itemHeight();
			},
			set itemHeight($$value) {
				itemHeight($$value);
				flushSync();
			},
			get Children() {
				return children();
			},
			set Children($$value) {
				children($$value);
				flushSync();
			},
			get onScrollEnd() {
				return onScrollEnd();
			},
			set onScrollEnd($$value) {
				onScrollEnd($$value);
				flushSync();
			},
			get onScrollTop() {
				return onScrollTop();
			},
			set onScrollTop($$value) {
				onScrollTop($$value);
				flushSync();
			}
		};
		var svelte_virtual_list_viewport = root$11();
		set_class(svelte_virtual_list_viewport, 1, "svelte-16nckvm");
		var svelte_virtual_list_contents = child(svelte_virtual_list_viewport);
		set_class(svelte_virtual_list_contents, 1, "svelte-16nckvm");
		each(svelte_virtual_list_contents, 21, () => get(visible), (row) => row.index, ($$anchor, row) => {
			var svelte_virtual_list_row = root_1$9();
			set_class(svelte_virtual_list_row, 1, "svelte-16nckvm");
			snippet(child(svelte_virtual_list_row), () => children() ?? noop, () => get(row).data);
			reset(svelte_virtual_list_row);
			append($$anchor, svelte_virtual_list_row);
		});
		reset(svelte_virtual_list_contents);
		bind_this(svelte_virtual_list_contents, ($$value) => set(contents, $$value), () => get(contents));
		reset(svelte_virtual_list_viewport);
		bind_this(svelte_virtual_list_viewport, ($$value) => set(viewport, $$value), () => get(viewport));
		template_effect(() => {
			set_style(svelte_virtual_list_viewport, `height: ${height() ?? ""};`);
			set_style(svelte_virtual_list_contents, `padding-top: ${get(top) ?? ""}px; padding-bottom: ${get(bottom) ?? ""}px;`);
		});
		event("scroll", svelte_virtual_list_viewport, handle_scroll);
		bind_element_size(svelte_virtual_list_viewport, "offsetHeight", ($$value) => set(viewport_height, $$value));
		append($$anchor, svelte_virtual_list_viewport);
		return pop($$exports);
	}
	create_custom_element(VirtualList, {
		items: {},
		height: {},
		itemHeight: {},
		Children: {},
		onScrollEnd: {},
		onScrollTop: {}
	}, [], [], { mode: "open" });
	//#endregion
	//#region src/ReactionBar.svelte
	var root_1$8 = /* @__PURE__ */ from_html(`<button type="button"><span class="uc-reaction-emoji svelte-bsisln"> </span> <span class="uc-reaction-count svelte-bsisln"> </span></button>`);
	var root_3$8 = /* @__PURE__ */ from_html(`<button type="button" class="uc-reaction-picker-item svelte-bsisln"> </button>`);
	var root_2$11 = /* @__PURE__ */ from_html(`<button type="button" class="uc-reaction-add svelte-bsisln" title="Add reaction" aria-label="Add reaction"><span aria-hidden="true" class="fa fa-smile-o"></span></button> <div popover="auto" class="uc-reaction-picker svelte-bsisln" role="dialog" aria-label="Emoji picker"></div>`, 1);
	var root$10 = /* @__PURE__ */ from_html(`<div class="uc-reaction-bar svelte-bsisln"><!> <!></div>`);
	var $$css$11 = {
		hash: "svelte-bsisln",
		code: ".uc-reaction-bar.svelte-bsisln {display:flex;flex-wrap:wrap;gap:var(--uc-chat-space-1);align-items:center;}.uc-reaction-pill.svelte-bsisln {display:inline-flex;align-items:center;gap:0.2em;padding:0.15em var(--uc-chat-space-2);border:1px solid var(--uc-chat-component-border-color);border-radius:var(--uc-chat-radius-pill);background:var(--uc-chat-surface-background-color);cursor:pointer;font-size:0.8em;font-family:inherit;color:inherit;transition:background-color 0.15s;}.uc-reaction-pill.svelte-bsisln:hover:not(:disabled) {background-color:var(--uc-chat-hover-background-color);}\n\n	/* \"You reacted\" is a state, and one device says it: the app's own primary,\n	   tinted into the fill and stated on the edge. It was --uc-chat-color-31, a\n	   fixed blue that ignored the app's theme entirely. */.uc-reaction-pill-active.svelte-bsisln {border-color:var(--uc-chat-accent-color);background-color:color-mix(\n			in srgb,\n			var(--uc-chat-accent-color) 12%,\n			var(--uc-chat-surface-background-color)\n		);}.uc-reaction-pill-readonly.svelte-bsisln {cursor:default;}.uc-reaction-emoji.svelte-bsisln {font-size:0.95em;line-height:1;}.uc-reaction-count.svelte-bsisln {font-size:0.85em;font-variant-numeric:tabular-nums;color:var(--uc-chat-component-text-muted-color);}.uc-reaction-pill-active.svelte-bsisln .uc-reaction-count:where(.svelte-bsisln) {color:var(--uc-chat-accent-color);font-weight:600;}\n\n	/* A bare glyph, not a dashed chip. The dashed circle was a third border style\n	   in a row that already had a solid pill and a solid reply button, and it\n	   asked to be noticed on every message that had no reactions at all. */.uc-reaction-add.svelte-bsisln {display:inline-flex;align-items:center;justify-content:center;padding:0.15em var(--uc-chat-space-2);border:1px solid transparent;border-radius:var(--uc-chat-radius-pill);background:none;cursor:pointer;font-size:0.8em;color:var(--uc-chat-component-text-muted-color);transition:background-color 0.15s, opacity 0.15s;anchor-name:var(--uc-reaction-anchor);}.uc-reaction-add.svelte-bsisln:hover {border-color:var(--uc-chat-component-border-color);background-color:var(--uc-chat-hover-background-color);color:var(--uc-chat-component-text-title-color);}\n\n	/* Revealed with the rest of the row's controls, and only where a row exists\n	   to hover — a bare bar keeps it visible. */.uc-channel-msg .uc-reaction-add.svelte-bsisln {opacity:0;}.uc-channel-msg:hover .uc-reaction-add.svelte-bsisln,\n	.uc-reaction-add.svelte-bsisln:focus-visible,\n	.uc-reaction-add.svelte-bsisln:focus {opacity:1;}\n\n	@media (hover: none) {.uc-channel-msg .uc-reaction-add.svelte-bsisln {opacity:1;}\n	}\n\n	@media (prefers-reduced-motion: reduce) {.uc-reaction-add.svelte-bsisln,\n		.uc-reaction-pill.svelte-bsisln {transition:none;}\n	}\n\n	/* A popover genuinely floats above the page, so this is the one place in the\n	   component where a drop shadow is doing real work. */.uc-reaction-picker.svelte-bsisln {flex-wrap:wrap;gap:0.15em;padding:var(--uc-chat-space-1);background:var(--uc-chat-surface-background-color);border:1px solid var(--uc-chat-component-border-color);border-radius:var(--uc-chat-radius-md);box-shadow:var(--uc-chat-shadow-md);width:12em;margin:0;inset:auto;position-anchor:var(--uc-reaction-anchor);position-area:top;}.uc-reaction-picker.svelte-bsisln:popover-open {display:flex;}.uc-reaction-picker-item.svelte-bsisln {display:inline-flex;align-items:center;justify-content:center;width:2em;height:2em;border:none;background:none;cursor:pointer;border-radius:var(--uc-chat-radius-sm);font-size:1em;}.uc-reaction-picker-item.svelte-bsisln:hover,\n	.uc-reaction-picker-item.svelte-bsisln:focus-visible {background-color:var(--uc-chat-hover-background-color);}"
	};
	function ReactionBar($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css$11);
		let reactions = prop($$props, "reactions", 23, () => []), onToggleReaction = prop($$props, "onToggleReaction", 7), readonly = prop($$props, "readonly", 7, false);
		/** @type {HTMLDivElement|undefined} */
		let pickerEl = /* @__PURE__ */ state(void 0);
		let pickerId = `uc-emoji-picker-${Math.random().toString(36).slice(2, 9)}`;
		const commonEmojis = [
			"👍",
			"👎",
			"❤️",
			"🎉",
			"😂",
			"👀",
			"🙏",
			"🔥",
			"✅",
			"❌",
			"🤔",
			"💯",
			"🚀",
			"👏",
			"😊"
		];
		function handleToggle(emoji) {
			if (readonly()) return;
			try {
				onToggleReaction()?.(emoji);
			} catch (e) {
				debugError("Failed to toggle reaction", e);
			}
		}
		function handlePickerSelect(emoji) {
			get(pickerEl)?.hidePopover();
			handleToggle(emoji);
		}
		var $$exports = {
			get reactions() {
				return reactions();
			},
			set reactions($$value = []) {
				reactions($$value);
				flushSync();
			},
			get onToggleReaction() {
				return onToggleReaction();
			},
			set onToggleReaction($$value) {
				onToggleReaction($$value);
				flushSync();
			},
			get readonly() {
				return readonly();
			},
			set readonly($$value = false) {
				readonly($$value);
				flushSync();
			}
		};
		var div = root$10();
		var node = child(div);
		each(node, 17, reactions, index, ($$anchor, reaction) => {
			var button = root_1$8();
			let classes;
			var span = child(button);
			var text = child(span, true);
			reset(span);
			var span_1 = sibling(span, 2);
			var text_1 = child(span_1, true);
			reset(span_1);
			reset(button);
			template_effect(() => {
				classes = set_class(button, 1, "uc-reaction-pill svelte-bsisln", null, classes, {
					"uc-reaction-pill-active": get(reaction).userReacted,
					"uc-reaction-pill-readonly": readonly()
				});
				set_attribute(button, "title", `${get(reaction).emoji ?? ""} ${get(reaction).count ?? ""}`);
				button.disabled = readonly();
				set_text(text, get(reaction).emoji);
				set_text(text_1, get(reaction).count);
			});
			delegated("click", button, () => handleToggle(get(reaction).emoji));
			append($$anchor, button);
		});
		var node_1 = sibling(node, 2);
		var consequent = ($$anchor) => {
			var fragment = root_2$11();
			var button_1 = first_child(fragment);
			var div_1 = sibling(button_1, 2);
			each(div_1, 21, () => commonEmojis, index, ($$anchor, emoji) => {
				var button_2 = root_3$8();
				var text_2 = child(button_2, true);
				reset(button_2);
				template_effect(() => set_text(text_2, get(emoji)));
				delegated("click", button_2, () => handlePickerSelect(get(emoji)));
				append($$anchor, button_2);
			});
			reset(div_1);
			bind_this(div_1, ($$value) => set(pickerEl, $$value), () => get(pickerEl));
			template_effect(() => {
				set_attribute(button_1, "popovertarget", pickerId);
				set_attribute(div_1, "id", pickerId);
			});
			append($$anchor, fragment);
		};
		if_block(node_1, ($$render) => {
			if (!readonly()) $$render(consequent);
		});
		reset(div);
		template_effect(() => set_style(div, `--uc-reaction-anchor: --${pickerId}`));
		append($$anchor, div);
		return pop($$exports);
	}
	delegate(["click"]);
	create_custom_element(ReactionBar, {
		reactions: {},
		onToggleReaction: {},
		readonly: {}
	}, [], [], { mode: "open" });
	//#endregion
	//#region src/ChannelMessageList.svelte
	var root_2$10 = /* @__PURE__ */ from_html(`<div class="uc-chat-day-info"><span class="uc-chat-day-info-text"> </span></div>`);
	var root_6$2 = /* @__PURE__ */ from_html(`<span class="uc-thread-new-badge svelte-2n6prp"> </span>`);
	var root_5$3 = /* @__PURE__ */ from_html(`<button type="button"><span class="fa fa-comment-o"></span> <!></button>`);
	var root_7 = /* @__PURE__ */ from_html(`<button type="button" class="uc-thread-reply-btn svelte-2n6prp" title="Reply in thread" aria-label="Reply in thread"><span class="fa fa-comment-o"></span></button>`);
	var root_3$7 = /* @__PURE__ */ from_html(`<div class="uc-chat-message uc-channel-msg"><div class="uc-chat-message-avatar"><!></div> <div class="uc-chat-message-content"><div class="uc-chat-message-byline"><span> </span> <span class="uc-chat-bullet">&bull;</span> <span class="uc-chat-time"> </span></div> <div class="uc-chat-message-text"><span> </span></div> <div class="uc-reactions-and-thread svelte-2n6prp"><!> <!></div></div></div>`);
	var root_8 = /* @__PURE__ */ from_html(`<div class="uc-chat-system-message"><div><span> </span></div></div>`);
	var root_1$7 = /* @__PURE__ */ from_html(`<div class="uc-channel-message-view svelte-2n6prp"><!> <!></div>`);
	var root_10 = /* @__PURE__ */ from_html(`<div class="uc-channel-empty svelte-2n6prp"></div>`);
	var root$9 = /* @__PURE__ */ from_html(`<div class="uc-channel-messages-wrapper svelte-2n6prp"><!></div>`);
	var $$css$10 = {
		hash: "svelte-2n6prp",
		code: "\n	/* The message row, the day divider, the system line and the avatar all live\n	   in styles.css now. This component used to carry a near-copy of every one of\n	   those rules, reaching into them through :global() so it could restate what\n	   MessageInfiniteList had already said — and the two copies had drifted. */.uc-channel-messages-wrapper.svelte-2n6prp {min-height:20em;height:100%;}.uc-channel-empty.svelte-2n6prp {height:100%;}.uc-channel-message-view.svelte-2n6prp {display:flex;flex-direction:column;padding:var(--uc-chat-space-1) var(--uc-chat-space-3);}\n\n	/* Supporting controls under a message: present for everyone who can use a\n	   pointer, but revealed on hover so five rows of chat are not five rows of\n	   buttons. Same rule the AI transcript applies to its copy button, including\n	   the touch fallback — nothing hovers on a touch screen. */.uc-reactions-and-thread.svelte-2n6prp {display:flex;align-items:center;gap:var(--uc-chat-space-1);margin-top:var(--uc-chat-space-1);flex-wrap:wrap;min-height:1.5em;}.uc-thread-replies-link.svelte-2n6prp {background:none;color:var(--uc-chat-component-text-muted-color);cursor:pointer;font-size:0.8em;font-family:inherit;padding:0.15em var(--uc-chat-space-2);border-radius:var(--uc-chat-radius-pill);border:1px solid transparent;display:inline-flex;align-items:center;gap:var(--uc-chat-space-1);}.uc-thread-replies-link.svelte-2n6prp:hover {border-color:var(--uc-chat-component-border-color);background-color:var(--uc-chat-hover-background-color);color:var(--uc-chat-component-text-title-color);}.uc-thread-replies-new.svelte-2n6prp {font-weight:600;color:var(--uc-chat-component-text-title-color);}.uc-thread-new-badge.svelte-2n6prp {display:inline-flex;align-items:center;justify-content:center;\n		/* Was --uc-chat-color-31 with a hardcoded #fff on top. */background-color:var(--uc-chat-accent-color);color:var(--uc-chat-accent-contrast-color);font-size:0.8em;font-weight:600;line-height:1;padding:0.2em 0.4em;border-radius:var(--uc-chat-radius-pill);min-width:1.4em;text-align:center;flex-shrink:0;}.uc-thread-reply-btn.svelte-2n6prp {background:none;border:1px solid transparent;border-radius:var(--uc-chat-radius-pill);color:var(--uc-chat-component-text-muted-color);cursor:pointer;font-size:0.8em;padding:0.15em var(--uc-chat-space-2);opacity:0;transition:opacity 0.15s;}.uc-channel-msg:hover .uc-thread-reply-btn,\n	.uc-thread-reply-btn.svelte-2n6prp:focus-visible {opacity:1;}.uc-thread-reply-btn.svelte-2n6prp:hover {color:var(--uc-chat-accent-color);border-color:var(--uc-chat-component-border-color);background-color:var(--uc-chat-hover-background-color);}\n\n	/* Nothing hovers on a touch screen. */\n	@media (hover: none) {.uc-thread-reply-btn.svelte-2n6prp {opacity:1;}\n	}\n\n	@media (prefers-reduced-motion: reduce) {.uc-thread-reply-btn.svelte-2n6prp {transition:none;}\n	}"
	};
	function ChannelMessageList($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css$10);
		const messageItem = ($$anchor, item = noop) => {
			var div = root_1$7();
			var node = child(div);
			var consequent = ($$anchor) => {
				var div_1 = root_2$10();
				var span = child(div_1);
				var text = child(span, true);
				reset(span);
				reset(div_1);
				template_effect(($0) => set_text(text, $0), [() => formatDateString(item().messageDate)]);
				append($$anchor, div_1);
			};
			if_block(node, ($$render) => {
				if (item().isDifferentDay) $$render(consequent);
			});
			var node_1 = sibling(node, 2);
			var consequent_4 = ($$anchor) => {
				var div_2 = root_3$7();
				var div_3 = child(div_2);
				Avatar(child(div_3), {
					get img() {
						return item().userImgUrl;
					},
					get name() {
						return item().userName;
					}
				});
				reset(div_3);
				var div_4 = sibling(div_3, 2);
				var div_5 = child(div_4);
				var span_1 = child(div_5);
				var text_1 = child(span_1, true);
				reset(span_1);
				var span_2 = sibling(span_1, 4);
				var text_2 = child(span_2, true);
				reset(span_2);
				reset(div_5);
				var div_6 = sibling(div_5, 2);
				var span_3 = child(div_6);
				var text_3 = child(span_3, true);
				reset(span_3);
				reset(div_6);
				var div_7 = sibling(div_6, 2);
				var node_3 = child(div_7);
				var consequent_1 = ($$anchor) => {
					{
						let $0 = /* @__PURE__ */ user_derived(() => item().reactions || []);
						ReactionBar($$anchor, {
							get reactions() {
								return get($0);
							},
							get readonly() {
								return get(isReadonly);
							},
							onToggleReaction: (emoji) => handleToggleReaction(item().messageId, emoji)
						});
					}
				};
				if_block(node_3, ($$render) => {
					if (item().reactions?.length > 0 || !get(isReadonly)) $$render(consequent_1);
				});
				var node_4 = sibling(node_3, 2);
				var consequent_3 = ($$anchor) => {
					var button = root_5$3();
					let classes;
					var text_4 = sibling(child(button));
					var node_5 = sibling(text_4);
					var consequent_2 = ($$anchor) => {
						var span_4 = root_6$2();
						var text_5 = child(span_4, true);
						reset(span_4);
						template_effect(() => {
							set_attribute(span_4, "aria-label", `${item().newReplyCount ?? ""} new replies`);
							set_text(text_5, item().newReplyCount);
						});
						append($$anchor, span_4);
					};
					if_block(node_5, ($$render) => {
						if (item().newReplyCount > 0) $$render(consequent_2);
					});
					reset(button);
					template_effect(() => {
						classes = set_class(button, 1, "uc-thread-replies-link svelte-2n6prp", null, classes, { "uc-thread-replies-new": item().newReplyCount > 0 });
						set_text(text_4, ` ${item().replyCount ?? ""} ${item().replyCount === 1 ? "reply" : "replies"} `);
					});
					delegated("click", button, () => handleOpenThread(item()));
					append($$anchor, button);
				};
				var alternate = ($$anchor) => {
					var button_1 = root_7();
					delegated("click", button_1, () => handleOpenThread(item()));
					append($$anchor, button_1);
				};
				if_block(node_4, ($$render) => {
					if (item().replyCount > 0) $$render(consequent_3);
					else $$render(alternate, -1);
				});
				reset(div_7);
				reset(div_4);
				reset(div_2);
				template_effect(() => {
					set_attribute(div_2, "data-id", item().messageId);
					set_text(text_1, item().userName);
					set_text(text_2, item().formatteTime);
					set_text(text_3, item().messageText);
				});
				append($$anchor, div_2);
			};
			var alternate_1 = ($$anchor) => {
				var div_8 = root_8();
				var div_9 = child(div_8);
				var span_5 = child(div_9);
				var text_6 = child(span_5, true);
				reset(span_5);
				reset(div_9);
				reset(div_8);
				template_effect(() => set_text(text_6, item().messageText));
				append($$anchor, div_8);
			};
			if_block(node_1, ($$render) => {
				if (item().userId !== "_*#SYSTEM#*_") $$render(consequent_4);
				else $$render(alternate_1, -1);
			});
			reset(div);
			append($$anchor, div);
		};
		let channelId = prop($$props, "channelId", 7), regionId = prop($$props, "regionId", 7), canReact = prop($$props, "canReact", 7, true);
		let channelState = getChannelState();
		let items = /* @__PURE__ */ state(proxy([]));
		let loading = /* @__PURE__ */ state(true);
		let oldChannelId = -1;
		let allFetched = false;
		const persists = 50;
		let isReadonly = /* @__PURE__ */ user_derived(() => !canReact());
		function handleMessageSent(e, data) {
			debugInfo(`ChannelMessageList event: ${EVENT_CHANNEL_MESSAGE_SENT}`, {
				event: e,
				data
			});
			if (data?.channelId === channelId()) handleNewMessage();
		}
		function handleAmsNewMessage(e, data) {
			debugInfo("uc-chat-new-message event (channel)", {
				e,
				data
			});
			const amsData = data?.amsdata;
			if (!amsData) return;
			if (amsData.type === "channel" && amsData.channelId === channelId()) if (!amsData.parentMessageId) handleNewMessage();
			else {
				const parent = get(items).find((m) => m.messageId === amsData.parentMessageId);
				if (parent) {
					parent.replyCount = (parent.replyCount || 0) + 1;
					parent.newReplyCount = (parent.newReplyCount || 0) + 1;
				}
			}
			else if (amsData.type === "channel_reaction" && amsData.channelId === channelId()) handleAmsReaction(amsData);
		}
		function handleAmsReaction(amsData) {
			const msg = get(items).find((m) => m.messageId === amsData.messageId);
			if (!msg) return;
			if (!msg.reactions) msg.reactions = [];
			const existing = msg.reactions.find((r) => r.emoji === amsData.emoji);
			if (amsData.action === "added") if (existing) existing.count++;
			else msg.reactions.push({
				emoji: amsData.emoji,
				count: 1,
				userReacted: false
			});
			else if (amsData.action === "removed") {
				if (existing) {
					existing.count--;
					if (existing.count <= 0) msg.reactions = msg.reactions.filter((r) => r.emoji !== amsData.emoji);
				}
			}
		}
		async function handleNewMessage() {
			await fetchNextRows(false);
			scrollToLastMessage();
		}
		function resetItems() {
			set(items, [], true);
			allFetched = false;
		}
		function getIsDifferentDay(index, newItems) {
			if (index === 0) {
				if (get(items).length === 0) return false;
				return isDifferentDay(newItems[index].messageDate, get(items)[get(items).length - 1].messageDate);
			}
			return isDifferentDay(newItems[index].messageDate, newItems[index - 1].messageDate);
		}
		async function fetchNextRows(older = true) {
			if (older && allFetched) return;
			set(loading, true);
			const lastMessageId = older ? get(items)[0]?.messageId : get(items)[get(items).length - 1]?.messageId;
			const res = await fetchChannelMessages({
				channelId: channelId(),
				lastMessageId,
				olderOrNewer: older ? "older" : "newer",
				regionId: regionId()
			});
			set(loading, false);
			if (older) {
				if (res.messages.length === 0) {
					allFetched = true;
					return;
				}
				if (res.messages.length < persists) allFetched = true;
			} else if (res.messages.length === 0) return;
			const msgs = res.messages.reverse();
			for (let i = 0; i < msgs.length; i++) {
				const msg = msgs[i];
				msg.formatteTime = formatTimeString(msg.messageDate);
				msg.isDifferentDay = getIsDifferentDay(i, msgs);
				if (!msg.reactions) msg.reactions = [];
			}
			if (older) set(items, [...msgs, ...get(items)], true);
			else set(items, [...get(items), ...msgs], true);
			debugTrace("ChannelMessageList", {
				items: get(items),
				allFetched,
				older
			});
			set(loading, false);
			if (!older) markChannelRead({
				channelId: channelId(),
				regionId: regionId()
			}).catch((err) => {
				debugInfo("markChannelRead error (newer fetch)", err);
			});
		}
		function scrollToLastMessage() {
			if (!get(items) || get(items).length === 0) return;
			setTimeout(() => {
				const viewport = document.querySelector(`#${regionId()} .uc-channel-message-body svelte-virtual-list-viewport`);
				if (!viewport) return;
				debugTrace("scrolling to bottom");
				viewport.scrollTo({
					top: viewport.scrollHeight,
					behavior: "smooth"
				});
			}, 50);
		}
		async function channelIdChanged(newChannelId) {
			debugTrace("channelIdChanged", {
				newChannelId,
				oldChannelId
			});
			oldChannelId = newChannelId;
			resetItems();
			await fetchNextRows();
			scrollToLastMessage();
			markChannelRead({
				channelId: newChannelId,
				regionId: regionId()
			}).catch((err) => {
				debugInfo("markChannelRead error (channel open)", err);
			});
			const ch = channelState.channels.find((c) => c.channelId === newChannelId);
			if (ch) {
				ch.unreadCount = 0;
				ch.hasNewThreadReplies = 0;
			}
		}
		user_effect(() => {
			if (channelId() && oldChannelId !== channelId()) channelIdChanged(channelId());
		});
		function handleScrollTop() {
			fetchNextRows(true);
		}
		async function handleToggleReaction(messageId, emoji) {
			const res = await toggleReaction({
				messageId,
				emoji,
				regionId: regionId()
			});
			const msg = get(items).find((m) => m.messageId === messageId);
			if (!msg) return;
			const existing = msg.reactions.find((r) => r.emoji === emoji);
			if (res.action === "added") if (existing) {
				existing.count++;
				existing.userReacted = true;
			} else msg.reactions.push({
				emoji,
				count: 1,
				userReacted: true
			});
			else if (res.action === "removed") {
				if (existing) {
					existing.count--;
					existing.userReacted = false;
					if (existing.count <= 0) msg.reactions = msg.reactions.filter((r) => r.emoji !== emoji);
				}
			}
		}
		function handleOpenThread(item) {
			item.newReplyCount = 0;
			const ch = channelState.channels.find((c) => c.channelId === channelId());
			if (ch) ch.hasNewThreadReplies = 0;
			openThread(channelState, item);
		}
		onMount(() => {
			set(loading, true);
			apex.jQuery(`#${regionId()}`).on(EVENT_CHANNEL_MESSAGE_SENT, handleMessageSent);
			apex.jQuery(document).on("uc-chat-new-message", handleAmsNewMessage);
		});
		onDestroy(() => {
			apex.jQuery(`#${regionId()}`).off(EVENT_CHANNEL_MESSAGE_SENT, handleMessageSent);
			apex.jQuery(document).off("uc-chat-new-message", handleAmsNewMessage);
		});
		var $$exports = {
			get channelId() {
				return channelId();
			},
			set channelId($$value) {
				channelId($$value);
				flushSync();
			},
			get regionId() {
				return regionId();
			},
			set regionId($$value) {
				regionId($$value);
				flushSync();
			},
			get canReact() {
				return canReact();
			},
			set canReact($$value = true) {
				canReact($$value);
				flushSync();
			}
		};
		var div_10 = root$9();
		var node_6 = child(div_10);
		var consequent_5 = ($$anchor) => {
			Spinner($$anchor, {});
		};
		var consequent_6 = ($$anchor) => {
			append($$anchor, root_10());
		};
		var alternate_2 = ($$anchor) => {
			VirtualList($$anchor, {
				get items() {
					return get(items);
				},
				height: "100%",
				onScrollTop: handleScrollTop,
				get Children() {
					return messageItem;
				}
			});
		};
		if_block(node_6, ($$render) => {
			if (get(loading) && get(items).length === 0) $$render(consequent_5);
			else if (get(items).length === 0) $$render(consequent_6, 1);
			else $$render(alternate_2, -1);
		});
		reset(div_10);
		append($$anchor, div_10);
		return pop($$exports);
	}
	delegate(["click"]);
	create_custom_element(ChannelMessageList, {
		channelId: {},
		regionId: {},
		canReact: {}
	}, [], [], { mode: "open" });
	//#endregion
	//#region src/ThreadPanel.svelte
	var root_2$9 = /* @__PURE__ */ from_html(`<div class="uc-thread-msg uc-thread-reply svelte-1gt67hl"><div class="uc-thread-msg-avatar svelte-1gt67hl"><!></div> <div class="uc-thread-msg-content svelte-1gt67hl"><div class="uc-thread-msg-meta svelte-1gt67hl"><span class="uc-thread-msg-name svelte-1gt67hl"> </span> <span class="uc-thread-msg-time svelte-1gt67hl"> </span></div> <div class="uc-thread-msg-text svelte-1gt67hl"> </div></div></div>`);
	var root_3$6 = /* @__PURE__ */ from_html(`<div class="uc-thread-footer svelte-1gt67hl"><!></div>`);
	var root$8 = /* @__PURE__ */ from_html(`<div class="uc-thread-panel svelte-1gt67hl"><div class="uc-thread-header svelte-1gt67hl"><h3 class="uc-thread-title svelte-1gt67hl">Thread</h3> <button type="button" class="t-Button t-Button--small t-Button--noLabel t-Button--icon t-Button--simple" title="Close thread" aria-label="Close thread"><span aria-hidden="true" class="t-Icon fa fa-close"></span></button></div> <div class="uc-thread-body svelte-1gt67hl"><div class="uc-thread-parent svelte-1gt67hl"><div class="uc-thread-msg svelte-1gt67hl"><div class="uc-thread-msg-avatar svelte-1gt67hl"><!></div> <div class="uc-thread-msg-content svelte-1gt67hl"><div class="uc-thread-msg-meta svelte-1gt67hl"><span class="uc-thread-msg-name svelte-1gt67hl"> </span> <span class="uc-thread-msg-time svelte-1gt67hl"> </span></div> <div class="uc-thread-msg-text svelte-1gt67hl"> </div></div></div></div> <div class="uc-thread-divider svelte-1gt67hl"><span class="svelte-1gt67hl"> </span></div> <!> <!></div> <!></div>`);
	var $$css$9 = {
		hash: "svelte-1gt67hl",
		code: "\n	/* A narrow panel, so it sets the avatar knob once and Avatar.svelte scales\n	   its initials to match. It used to declare a third avatar size (1.8em) and a\n	   third radius (0.4em) for the same object the two transcripts already\n	   styled, then reach into Avatar with :global() to shrink the glyph. */.uc-thread-panel.svelte-1gt67hl {--uc-chat-avatar-size: 1.75em;display:flex;flex-direction:column;height:100%;max-height:100%;min-height:0;overflow:hidden;background-color:var(--uc-chat-surface-background-color);}.uc-thread-header.svelte-1gt67hl {background-color:var(--uc-chat-surface-background-color);\n		/* Was 42px while the channel header beside it was 48px: two \"top bars\" at\n		   two heights, side by side. */min-height:var(--uc-chat-bar-height);display:flex;align-items:center;justify-content:space-between;gap:var(--uc-chat-space-2);padding:var(--uc-chat-space-1) var(--uc-chat-space-2)\n			var(--uc-chat-space-1) var(--uc-chat-space-3);flex:0 0 auto;border-bottom:1px solid var(--uc-chat-component-border-color);}.uc-thread-title.svelte-1gt67hl {margin:0;font-size:1em;font-weight:600;letter-spacing:0.01em;color:var(--uc-chat-component-text-title-color);}.uc-thread-body.svelte-1gt67hl {flex:1;min-height:0;overflow-y:auto;padding:var(--uc-chat-space-2) var(--uc-chat-space-3);background-color:var(--uc-chat-canvas-background-color);}.uc-thread-parent.svelte-1gt67hl {padding-bottom:var(--uc-chat-space-1);}.uc-thread-msg.svelte-1gt67hl {display:flex;align-items:flex-start;gap:var(--uc-chat-space-2);padding:var(--uc-chat-space-1) 0;}.uc-thread-msg-avatar.svelte-1gt67hl {width:var(--uc-chat-avatar-size);height:var(--uc-chat-avatar-size);border-radius:var(--uc-chat-radius-md);overflow:hidden;flex-shrink:0;}.uc-thread-msg-content.svelte-1gt67hl {min-width:0;flex:1;}.uc-thread-msg-meta.svelte-1gt67hl {display:flex;align-items:baseline;gap:var(--uc-chat-space-1);font-size:0.75em;line-height:1.4;}.uc-thread-msg-name.svelte-1gt67hl {font-weight:600;color:var(--uc-chat-component-text-title-color);}.uc-thread-msg-time.svelte-1gt67hl {color:var(--uc-chat-component-text-muted-color);}\n\n	/* Fill plus a hairline, matching the transcript it belongs to. It carried a\n	   fill AND a 0.5px border AND a drop shadow. */.uc-thread-msg-text.svelte-1gt67hl {font-size:0.8em;font-weight:400;line-height:1.45;margin-top:0.15em;padding:var(--uc-chat-space-2) var(--uc-chat-space-3);background-color:var(--uc-chat-surface-background-color);border:1px solid var(--uc-chat-component-border-color);border-radius:var(--uc-chat-radius-md);word-break:break-word;}.uc-thread-divider.svelte-1gt67hl {border-top:1px solid var(--uc-chat-component-inner-border-color);text-align:center;margin:var(--uc-chat-space-1) 0 var(--uc-chat-space-2);padding-top:var(--uc-chat-space-2);}.uc-thread-divider.svelte-1gt67hl span:where(.svelte-1gt67hl) {font-size:0.75em;color:var(--uc-chat-component-text-muted-color);}\n\n	/* The 0.5em indent that used to be here gave the replies a second left edge:\n	   the parent's avatar started at one x, every reply's at another, for no\n	   reason the divider above them did not already state. */.uc-thread-footer.svelte-1gt67hl {display:flex;flex-direction:column;justify-content:center;background-color:var(--uc-chat-surface-background-color);border-top:1px solid var(--uc-chat-component-border-color);flex:0 0 auto;z-index:1;\n		/* Was a fixed 50px, which clipped the composer as soon as its textarea\n		   grew past one line. */min-height:var(--uc-chat-bar-height);}"
	};
	function ThreadPanel($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css$9);
		let regionId = prop($$props, "regionId", 7), channelId = prop($$props, "channelId", 7), parentMessage = prop($$props, "parentMessage", 7), canWriteThread = prop($$props, "canWriteThread", 7, false), onClose = prop($$props, "onClose", 7);
		let replies = /* @__PURE__ */ state(proxy([]));
		let loading = /* @__PURE__ */ state(true);
		let oldParentId = null;
		async function loadReplies() {
			set(loading, true);
			try {
				const msgs = (await fetchThreadMessages({
					parentMessageId: parentMessage().messageId,
					regionId: regionId()
				})).messages.reverse();
				for (let msg of msgs) msg.formatteTime = formatTimeString(msg.messageDate);
				set(replies, msgs, true);
				markChannelRead({
					channelId: channelId(),
					regionId: regionId()
				}).catch((err) => debugInfo("markChannelRead error (thread open)", err));
			} catch (e) {
				debugError("Failed to load thread messages", e);
			} finally {
				set(loading, false);
			}
		}
		user_effect(() => {
			if (parentMessage()?.messageId && parentMessage().messageId !== oldParentId) {
				oldParentId = parentMessage().messageId;
				set(replies, [], true);
				loadReplies();
			}
		});
		async function handleSend(messageText) {
			const res = await sendThreadMessage({
				channelId: channelId(),
				parentMessageId: parentMessage().messageId,
				messageText,
				regionId: regionId()
			});
			debugInfo("Thread message sent", { messageId: res?.messageId });
			let newMsg = {
				messageId: res.messageId,
				messageText,
				messageDate: (/* @__PURE__ */ new Date()).toISOString(),
				userId: "me",
				userName: "You",
				formatteTime: formatTimeString((/* @__PURE__ */ new Date()).toISOString())
			};
			set(replies, [...get(replies), newMsg], true);
			setTimeout(() => {
				if (get(scrollContainer)) get(scrollContainer).scrollTo({
					top: get(scrollContainer).scrollHeight,
					behavior: "smooth"
				});
			}, 50);
		}
		let scrollContainer = /* @__PURE__ */ state(null);
		async function handleNewThreadReply() {
			const msgs = (await fetchThreadMessages({
				parentMessageId: parentMessage().messageId,
				regionId: regionId()
			})).messages.reverse();
			for (let msg of msgs) msg.formatteTime = formatTimeString(msg.messageDate);
			set(replies, msgs, true);
			setTimeout(() => {
				if (get(scrollContainer)) get(scrollContainer).scrollTo({
					top: get(scrollContainer).scrollHeight,
					behavior: "smooth"
				});
			}, 50);
		}
		function handleAmsNewMessage(e, data) {
			debugInfo("uc-chat-new-message event (thread)", {
				e,
				data
			});
			const amsData = data?.amsdata;
			if (amsData?.type === "channel" && amsData?.parentMessageId === parentMessage().messageId) handleNewThreadReply();
		}
		onMount(() => {
			apex.jQuery(document).on("uc-chat-new-message", handleAmsNewMessage);
		});
		onDestroy(() => {
			apex.jQuery(document).off("uc-chat-new-message", handleAmsNewMessage);
		});
		var $$exports = {
			get regionId() {
				return regionId();
			},
			set regionId($$value) {
				regionId($$value);
				flushSync();
			},
			get channelId() {
				return channelId();
			},
			set channelId($$value) {
				channelId($$value);
				flushSync();
			},
			get parentMessage() {
				return parentMessage();
			},
			set parentMessage($$value) {
				parentMessage($$value);
				flushSync();
			},
			get canWriteThread() {
				return canWriteThread();
			},
			set canWriteThread($$value = false) {
				canWriteThread($$value);
				flushSync();
			},
			get onClose() {
				return onClose();
			},
			set onClose($$value) {
				onClose($$value);
				flushSync();
			}
		};
		var div = root$8();
		var div_1 = child(div);
		var button = sibling(child(div_1), 2);
		reset(div_1);
		var div_2 = sibling(div_1, 2);
		var div_3 = child(div_2);
		var div_4 = child(div_3);
		var div_5 = child(div_4);
		Avatar(child(div_5), {
			get img() {
				return parentMessage().userImgUrl;
			},
			get name() {
				return parentMessage().userName;
			}
		});
		reset(div_5);
		var div_6 = sibling(div_5, 2);
		var div_7 = child(div_6);
		var span = child(div_7);
		var text = child(span, true);
		reset(span);
		var span_1 = sibling(span, 2);
		var text_1 = child(span_1, true);
		reset(span_1);
		reset(div_7);
		var div_8 = sibling(div_7, 2);
		var text_2 = child(div_8, true);
		reset(div_8);
		reset(div_6);
		reset(div_4);
		reset(div_3);
		var div_9 = sibling(div_3, 2);
		var span_2 = child(div_9);
		var text_3 = child(span_2);
		reset(span_2);
		reset(div_9);
		var node_1 = sibling(div_9, 2);
		var consequent = ($$anchor) => {
			Spinner($$anchor, {});
		};
		if_block(node_1, ($$render) => {
			if (get(loading)) $$render(consequent);
		});
		each(sibling(node_1, 2), 17, () => get(replies), index, ($$anchor, reply) => {
			var div_10 = root_2$9();
			var div_11 = child(div_10);
			Avatar(child(div_11), {
				get img() {
					return get(reply).userImgUrl;
				},
				get name() {
					return get(reply).userName;
				}
			});
			reset(div_11);
			var div_12 = sibling(div_11, 2);
			var div_13 = child(div_12);
			var span_3 = child(div_13);
			var text_4 = child(span_3, true);
			reset(span_3);
			var span_4 = sibling(span_3, 2);
			var text_5 = child(span_4, true);
			reset(span_4);
			reset(div_13);
			var div_14 = sibling(div_13, 2);
			var text_6 = child(div_14, true);
			reset(div_14);
			reset(div_12);
			reset(div_10);
			template_effect(() => {
				set_text(text_4, get(reply).userName);
				set_text(text_5, get(reply).formatteTime);
				set_text(text_6, get(reply).messageText);
			});
			append($$anchor, div_10);
		});
		reset(div_2);
		bind_this(div_2, ($$value) => set(scrollContainer, $$value), () => get(scrollContainer));
		var node_4 = sibling(div_2, 2);
		var consequent_1 = ($$anchor) => {
			var div_15 = root_3$6();
			MessageComposer(child(div_15), {
				onSend: handleSend,
				placeholder: "Reply in thread..."
			});
			reset(div_15);
			append($$anchor, div_15);
		};
		if_block(node_4, ($$render) => {
			if (canWriteThread()) $$render(consequent_1);
		});
		reset(div);
		template_effect(() => {
			set_text(text, parentMessage().userName);
			set_text(text_1, parentMessage().formatteTime || "");
			set_text(text_2, parentMessage().messageText);
			set_text(text_3, `${(parentMessage().replyCount || get(replies).length) ?? ""} ${(parentMessage().replyCount || get(replies).length) === 1 ? "reply" : "replies"}`);
		});
		delegated("click", button, function(...$$args) {
			onClose()?.apply(this, $$args);
		});
		append($$anchor, div);
		return pop($$exports);
	}
	delegate(["click"]);
	create_custom_element(ThreadPanel, {
		regionId: {},
		channelId: {},
		parentMessage: {},
		canWriteThread: {},
		onClose: {}
	}, [], [], { mode: "open" });
	//#endregion
	//#region src/ChannelChatPane.svelte
	var root_2$8 = /* @__PURE__ */ from_html(`<span class="uc-channel-topic svelte-1oeo8by"> </span>`);
	var root_3$5 = /* @__PURE__ */ from_html(`<span class="uc-channel-readonly-badge svelte-1oeo8by"><span aria-hidden="true" class="fa fa-lock"></span> </span>`);
	var root_4$3 = /* @__PURE__ */ from_html(`<div class="uc-channel-thread-panel svelte-1oeo8by"><!></div>`);
	var root_5$2 = /* @__PURE__ */ from_html(`<div class="uc-channel-message-footer svelte-1oeo8by"><!></div>`);
	var root_1$6 = /* @__PURE__ */ from_html(`<div class="uc-channel-message-view svelte-1oeo8by"><div class="uc-channel-message-header svelte-1oeo8by"><button type="button" title="back to channel list" aria-label="back to channel list" class="uc-channel-back-btn t-Button t-Button--small t-Button--noLabel t-Button--icon t-Button--simple svelte-1oeo8by"><span aria-hidden="true" class="t-Icon fa fa-chevron-left"></span></button> <div class="uc-channel-header-info svelte-1oeo8by"><h2 class="uc-channel-name svelte-1oeo8by"><span aria-hidden="true" class="fa fa-hashtag uc-channel-name-icon svelte-1oeo8by"></span> </h2> <!></div> <!></div> <div class="uc-channel-content-area svelte-1oeo8by"><div class="uc-channel-message-body svelte-1oeo8by"><!></div> <!></div> <!></div>`);
	var root_6$1 = /* @__PURE__ */ from_html(`<div class="uc-channel-empty-state svelte-1oeo8by"><span aria-hidden="true" class="fa fa-th-list uc-channel-empty-icon svelte-1oeo8by"></span> <p class="uc-channel-empty-title svelte-1oeo8by">No channel selected</p> <p class="uc-channel-empty-hint svelte-1oeo8by">Choose a channel from the list to start messaging</p></div>`);
	var root$7 = /* @__PURE__ */ from_html(`<div><div class="uc-channel-left-pane svelte-1oeo8by"><!></div> <div class="uc-channel-right-pane svelte-1oeo8by"><!></div></div>`);
	var $$css$8 = {
		hash: "svelte-1oeo8by",
		code: ".uc-channel-pane.svelte-1oeo8by {display:grid;grid-template-columns:1fr 2fr;height:100%;max-height:100%;min-height:0;overflow:hidden;}.uc-channel-left-pane.svelte-1oeo8by {min-height:0;max-height:inherit;overflow-y:auto;display:flex;flex-direction:column;border-right:1px solid var(--uc-chat-component-border-color);background-color:var(--uc-chat-surface-background-color);}.uc-channel-right-pane.svelte-1oeo8by {min-height:0;height:100%;overflow:hidden;display:flex;flex-direction:column;\n		/* The pane owns its surface so the translucent canvas tint below has\n		   something predictable to composite over. */background-color:var(--uc-chat-surface-background-color);}.uc-channel-message-view.svelte-1oeo8by {display:flex;flex-direction:column;max-height:100%;height:100%;min-height:0;\n		/* One step recessed from the surface, in whichever direction the host\n		   theme tints. Was --uc-chat-footer-background-color: a flat #f2f2f2 that\n		   also served as hover feedback and as the day-divider backdrop. */background-color:var(--uc-chat-canvas-background-color);overflow:hidden;}\n\n	/* Chrome sits on the plain surface and is divided from the transcript by a\n	   hairline, the way an APEX region header is. The drop shadow it used to\n	   carry smudged onto the canvas and read as a rendering artefact rather than\n	   a boundary. */.uc-channel-message-header.svelte-1oeo8by {background-color:var(--uc-chat-surface-background-color);\n		/* Was a raw 48px in an em-only codebase, and 6px taller than the thread\n		   header that opens right beside it. Both bars derive from one measure. */min-height:var(--uc-chat-bar-height);border-bottom:1px solid var(--uc-chat-component-border-color);display:flex;align-items:center;padding:var(--uc-chat-space-1) var(--uc-chat-space-3);flex:0 0 auto;z-index:1;gap:var(--uc-chat-space-2);}.uc-channel-header-info.svelte-1oeo8by {flex:1;min-width:0;}.uc-channel-name.svelte-1oeo8by {margin:0;padding:0;font-weight:600;color:var(--uc-chat-component-text-title-color);font-size:1em;letter-spacing:0.01em;display:flex;align-items:baseline;gap:var(--uc-chat-space-1);min-width:0;}.uc-channel-name-icon.svelte-1oeo8by {font-size:0.85em;color:var(--uc-chat-component-text-muted-color);}.uc-channel-topic.svelte-1oeo8by {font-size:0.75em;color:var(--uc-chat-component-text-muted-color);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;display:block;}\n\n	/* Quiet, because it states a fact rather than raising an alarm: no fill, one\n	   hairline, and the shared small radius instead of a one-off 0.3em. */.uc-channel-readonly-badge.svelte-1oeo8by {font-size:0.75em;color:var(--uc-chat-component-text-muted-color);display:flex;align-items:center;gap:var(--uc-chat-space-1);flex-shrink:0;padding:0.15em var(--uc-chat-space-2);border:1px solid var(--uc-chat-component-border-color);border-radius:var(--uc-chat-radius-sm);white-space:nowrap;}.uc-channel-content-area.svelte-1oeo8by {display:flex;flex:1;min-height:0;overflow:hidden;}.uc-channel-message-body.svelte-1oeo8by {flex:1;min-height:0;min-width:0;overflow-y:auto;position:relative;}.uc-channel-thread-panel.svelte-1oeo8by {width:20em;border-left:1px solid var(--uc-chat-component-border-color);display:flex;flex-direction:column;overflow:hidden;flex-shrink:0;}.uc-channel-message-footer.svelte-1oeo8by {display:flex;flex-direction:column;justify-content:center;background-color:var(--uc-chat-surface-background-color);border-top:1px solid var(--uc-chat-component-border-color);flex:0 0 auto;z-index:1;\n		/* Was a fixed 50px, which clipped the composer as soon as the textarea grew\n		   past one line (it is allowed to reach 10em). */min-height:var(--uc-chat-bar-height);}.uc-channel-empty-state.svelte-1oeo8by {display:flex;flex-direction:column;align-items:center;justify-content:center;height:100%;gap:var(--uc-chat-space-2);color:var(--uc-chat-component-text-muted-color);padding:var(--uc-chat-space-4);text-align:center;}.uc-channel-empty-icon.svelte-1oeo8by {font-size:2.5em;\n		/* Was opacity 0.4 on top of an already-muted colour, which faded the glyph\n		   almost into the backdrop in a dark theme. */color:var(--uc-chat-component-text-muted-color);opacity:0.55;margin-bottom:var(--uc-chat-space-1);}.uc-channel-empty-title.svelte-1oeo8by {margin:0;font-size:1em;font-weight:600;color:var(--uc-chat-component-text-title-color);}.uc-channel-empty-hint.svelte-1oeo8by {margin:0;font-size:0.85em;max-width:24em;}.uc-channel-back-btn.svelte-1oeo8by {display:none;}\n\n	/* Responsive: mobile shows either list or messages */\n	@container (max-width: 499px) {.uc-channel-pane.svelte-1oeo8by {display:block;}.uc-channel-right-pane.svelte-1oeo8by {display:none;}.uc-channel-open.svelte-1oeo8by .uc-channel-left-pane:where(.svelte-1oeo8by) {display:none;}.uc-channel-open.svelte-1oeo8by .uc-channel-right-pane:where(.svelte-1oeo8by) {display:flex;}.uc-channel-back-btn.svelte-1oeo8by {display:inline-flex;}.uc-channel-thread-panel.svelte-1oeo8by {width:100%;}\n	}"
	};
	function ChannelChatPane($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css$8);
		let regionId = prop($$props, "regionId", 7);
		let channelState = createChannelState();
		let canWrite = /* @__PURE__ */ user_derived(() => !!channelState.currentChannel?.canWrite);
		let canReact = /* @__PURE__ */ user_derived(() => !!channelState.currentChannel?.canReact);
		async function handleSend(messageText) {
			if (!channelState.currentChannel) return;
			const res = await sendChannelMessage({
				channelId: channelState.currentChannel.channelId,
				messageText,
				regionId: regionId()
			});
			debugInfo("Channel message sent", {
				channelId: channelState.currentChannel.channelId,
				messageId: res?.messageId
			});
			triggerEvent(EVENT_CHANNEL_MESSAGE_SENT, {
				channelId: channelState.currentChannel.channelId,
				messageId: res?.messageId
			}, regionId());
		}
		function clearChannel() {
			channelState.currentChannel = null;
		}
		function handleAmsNewMessage(_e, data) {
			const amsData = data?.amsdata;
			if (!amsData) return;
			if (amsData.type === "channel_reaction") return;
			if (amsData.type !== "channel") return;
			const { channelId: eventChannelId, parentMessageId } = amsData;
			const isCurrentChannel = channelState.currentChannel?.channelId === eventChannelId;
			const ch = channelState.channels.find((c) => c.channelId === eventChannelId);
			if (!ch) return;
			if (!parentMessageId) {
				if (!isCurrentChannel) ch.unreadCount = (ch.unreadCount || 0) + 1;
			} else if (!(isCurrentChannel && channelState.activeThread?.parentMessage?.messageId === parentMessageId)) ch.hasNewThreadReplies = 1;
		}
		onMount(() => {
			apex.jQuery(document).on("uc-chat-new-message", handleAmsNewMessage);
		});
		onDestroy(() => {
			apex.jQuery(document).off("uc-chat-new-message", handleAmsNewMessage);
		});
		var $$exports = {
			get regionId() {
				return regionId();
			},
			set regionId($$value) {
				regionId($$value);
				flushSync();
			}
		};
		var div = root$7();
		let classes;
		var div_1 = child(div);
		ChannelList(child(div_1), { get regionId() {
			return regionId();
		} });
		reset(div_1);
		var div_2 = sibling(div_1, 2);
		var node_1 = child(div_2);
		var consequent_4 = ($$anchor) => {
			var div_3 = root_1$6();
			var div_4 = child(div_3);
			var button = child(div_4);
			var div_5 = sibling(button, 2);
			var h2 = child(div_5);
			var text = sibling(child(h2));
			reset(h2);
			var node_2 = sibling(h2, 2);
			var consequent = ($$anchor) => {
				var span = root_2$8();
				var text_1 = child(span, true);
				reset(span);
				template_effect(() => set_text(text_1, channelState.currentChannel.channelTopic));
				append($$anchor, span);
			};
			if_block(node_2, ($$render) => {
				if (channelState.currentChannel.channelTopic) $$render(consequent);
			});
			reset(div_5);
			var node_3 = sibling(div_5, 2);
			var consequent_1 = ($$anchor) => {
				var span_1 = root_3$5();
				var text_2 = sibling(child(span_1));
				reset(span_1);
				template_effect(() => {
					set_attribute(span_1, "title", `${get(canReact) ? "React only" : "Read-only"} channel`);
					set_text(text_2, ` ${get(canReact) ? "React only" : "Read-only"}`);
				});
				append($$anchor, span_1);
			};
			if_block(node_3, ($$render) => {
				if (!get(canWrite)) $$render(consequent_1);
			});
			reset(div_4);
			var div_6 = sibling(div_4, 2);
			var div_7 = child(div_6);
			ChannelMessageList(child(div_7), {
				get regionId() {
					return regionId();
				},
				get channelId() {
					return channelState.currentChannel.channelId;
				},
				get canReact() {
					return get(canReact);
				}
			});
			reset(div_7);
			var node_5 = sibling(div_7, 2);
			var consequent_2 = ($$anchor) => {
				var div_8 = root_4$3();
				var node_6 = child(div_8);
				{
					let $0 = /* @__PURE__ */ user_derived(() => !!channelState.currentChannel?.canWriteThread);
					ThreadPanel(node_6, {
						get regionId() {
							return regionId();
						},
						get channelId() {
							return channelState.currentChannel.channelId;
						},
						get parentMessage() {
							return channelState.activeThread.parentMessage;
						},
						get canWriteThread() {
							return get($0);
						},
						onClose: () => closeThread(channelState)
					});
				}
				reset(div_8);
				append($$anchor, div_8);
			};
			if_block(node_5, ($$render) => {
				if (channelState.activeThread) $$render(consequent_2);
			});
			reset(div_6);
			var node_7 = sibling(div_6, 2);
			var consequent_3 = ($$anchor) => {
				var div_9 = root_5$2();
				MessageComposer(child(div_9), {
					onSend: handleSend,
					get placeholder() {
						return `Message #${channelState.currentChannel.channelName ?? ""}...`;
					}
				});
				reset(div_9);
				append($$anchor, div_9);
			};
			if_block(node_7, ($$render) => {
				if (get(canWrite) && !channelState.activeThread) $$render(consequent_3);
			});
			reset(div_3);
			template_effect(() => set_text(text, ` ${channelState.currentChannel.channelName ?? ""}`));
			delegated("click", button, clearChannel);
			append($$anchor, div_3);
		};
		var alternate = ($$anchor) => {
			append($$anchor, root_6$1());
		};
		if_block(node_1, ($$render) => {
			if (channelState.currentChannel) $$render(consequent_4);
			else $$render(alternate, -1);
		});
		reset(div_2);
		reset(div);
		template_effect(() => classes = set_class(div, 1, "uc-channel-pane svelte-1oeo8by", null, classes, { "uc-channel-open": !!channelState.currentChannel }));
		append($$anchor, div);
		return pop($$exports);
	}
	delegate(["click"]);
	create_custom_element(ChannelChatPane, { regionId: {} }, [], [], { mode: "open" });
	//#endregion
	//#region src/ChatsList.svelte
	var root_2$7 = /* @__PURE__ */ from_html(`<li class="uc-chat-li svelte-zcohgq"><button type="button" class="uc-chat-button svelte-zcohgq"><div><div class="uc-chat-avatar svelte-zcohgq"><!></div> <div class="uc-chat-info svelte-zcohgq"><div class="uc-chat-name svelte-zcohgq"><div class="uc-chat-new-message svelte-zcohgq"></div> </div> <div class="uc-chat-preview svelte-zcohgq"><div class="uc-chat-preview-msg u-lineclamp-1 svelte-zcohgq"> </div> <div class="uc-chat-preview-time svelte-zcohgq"> </div></div></div></div></button></li>`);
	var root$6 = /* @__PURE__ */ from_html(`<ul class="uc-chat-ul svelte-zcohgq"><!> <!></ul>`);
	var $$css$7 = {
		hash: "svelte-zcohgq",
		code: "\n  @keyframes svelte-zcohgq-ping {\n    75%,\n    100% {\n      transform: scale(2);\n      opacity: 0;\n    }\n  }.uc-chat-li.svelte-zcohgq {list-style:none;}\n\n  /* One avatar knob for the whole row: Avatar.svelte scales its initials from\n     the same token, so the tile and the glyph can no longer disagree. The row\n     must stay at 1em for that em to mean what it says. */.uc-chat-item.svelte-zcohgq {--uc-chat-avatar-size: 2.5em;padding:var(--uc-chat-space-3) var(--uc-chat-space-2);\n    /* 0.5px is not a length any display can draw: it rounds to 0 or 1 device\n       pixel depending on the pixel ratio, so rows disagreed with each other on\n       whether they had a divider at all. Rules between rows inside one pane are\n       divisions, not edges, so they use the inner-border token. */border-bottom:1px solid var(--uc-chat-component-inner-border-color);display:flex;align-items:center;gap:var(--uc-chat-space-2);\n    /* The selected row is marked by a rail plus a tint — the rail alone is\n       invisible when scanning a long list, the tint alone (2.5% alpha) is too\n       quiet to find. The colour is the app's own primary, not the fixed blue\n       --u-color-31 that used to make every app's chat blue regardless of its\n       theme. */border-left:0.1875em solid transparent;}.uc-chat-new-message.svelte-zcohgq {display:none;}.uc-chat-item.uc-chat-item-recent.svelte-zcohgq .uc-chat-new-message:where(.svelte-zcohgq) {display:inline-block;width:0.4em;height:0.4em;margin-right:0.4em;background-color:var(--uc-chat-accent-color);border-radius:var(--uc-chat-radius-pill);\n    animation: svelte-zcohgq-ping 1s cubic-bezier(0, 0, 0.2, 1) 5;flex-shrink:0;}\n\n  @media (prefers-reduced-motion: reduce) {.uc-chat-item.uc-chat-item-recent.svelte-zcohgq .uc-chat-new-message:where(.svelte-zcohgq) {\n      animation: none;}\n  }.uc-chat-avatar.svelte-zcohgq {height:var(--uc-chat-avatar-size);width:var(--uc-chat-avatar-size);border-radius:var(--uc-chat-radius-md);overflow:hidden;flex-shrink:0;}.uc-chat-name.svelte-zcohgq {font-weight:600;\n    /* Was --uc-chat-component-text-title-colo — a variable that does not exist,\n       so the declaration was discarded and the name simply inherited. */color:var(--uc-chat-component-text-title-color);font-size:0.9em;margin-bottom:0.1em;display:flex;align-items:center;min-width:0;}.uc-chat-info.svelte-zcohgq {display:flex;flex-direction:column;justify-content:center;flex-grow:1;min-width:0;}.uc-chat-preview.svelte-zcohgq {display:flex;justify-content:space-between;align-items:baseline;gap:var(--uc-chat-space-2);font-size:0.8em;color:var(--uc-chat-component-text-muted-color);}.uc-chat-preview-msg.svelte-zcohgq {min-width:0;}.uc-chat-ul.svelte-zcohgq {margin:0;padding:0;}.uc-chat-preview-time.svelte-zcohgq {text-align:right;white-space:nowrap;flex-shrink:0;}.uc-chat-item-active.svelte-zcohgq {border-left-color:var(--uc-chat-accent-color);background-color:var(--uc-chat-hover-background-color);}"
	};
	function ChatsList($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css$7);
		const regionId = prop($$props, "regionId", 7);
		const chatState = getChatState();
		let chats = /* @__PURE__ */ state(proxy([]));
		let loading = /* @__PURE__ */ state(true);
		async function handleNewMessage() {
			const { data: newChats } = await fetchChats({
				offset: 0,
				regionId: regionId()
			});
			set(chats, newChats, true);
		}
		onMount(async () => {
			debugTrace("ChatsList onMount");
			const { data } = await fetchChats({
				offset: 0,
				regionId: regionId()
			});
			set(loading, false);
			set(chats, data, true);
			apex.jQuery(document).on("uc-chat-new-message", handleNewMessage);
		});
		onDestroy(() => {
			apex.jQuery(document).off("uc-chat-new-message", handleNewMessage);
		});
		const onClick = (e, chat) => {
			apex.jQuery(e.target).closest(".uc-chat-item").removeClass("uc-chat-item-recent");
			openChat(chatState, {
				roomId: chat.roomId,
				roomName: chat.roomName,
				userIds: chat.userIds.split(":")
			});
		};
		var $$exports = {
			get regionId() {
				return regionId();
			},
			set regionId($$value) {
				regionId($$value);
				flushSync();
			}
		};
		var ul = root$6();
		var node = child(ul);
		var consequent = ($$anchor) => {
			Spinner($$anchor, {});
		};
		if_block(node, ($$render) => {
			if (get(loading)) $$render(consequent);
		});
		each(sibling(node, 2), 17, () => get(chats), index, ($$anchor, chat) => {
			var li = root_2$7();
			var button = child(li);
			var div = child(button);
			let classes;
			var div_1 = child(div);
			Avatar(child(div_1), {
				get img() {
					return get(chat).userImgUrl;
				},
				get name() {
					return get(chat).roomName;
				}
			});
			reset(div_1);
			var div_2 = sibling(div_1, 2);
			var div_3 = child(div_2);
			var text = sibling(child(div_3));
			reset(div_3);
			var div_4 = sibling(div_3, 2);
			var div_5 = child(div_4);
			var text_1 = child(div_5, true);
			reset(div_5);
			var div_6 = sibling(div_5, 2);
			var text_2 = child(div_6, true);
			reset(div_6);
			reset(div_4);
			reset(div_2);
			reset(div);
			reset(button);
			reset(li);
			template_effect(($0, $1) => {
				set_attribute(button, "data-id", get(chat).roomId);
				set_attribute(button, "aria-current", chatState.currChat?.roomId === get(chat).roomId ? "true" : void 0);
				classes = set_class(div, 1, "uc-chat-item svelte-zcohgq", null, classes, $0);
				set_text(text, ` ${get(chat).roomName ?? ""}`);
				set_text(text_1, get(chat).lastMessageText);
				set_text(text_2, $1);
			}, [() => ({
				"uc-chat-item-active": chatState.currChat?.roomId === get(chat).roomId,
				"uc-chat-item-recent": new Date(get(chat).lastMessageDate).getTime() > (/* @__PURE__ */ new Date()).getTime() - 1e3 * 60 && chatState.currChat?.roomId !== get(chat).roomId
			}), () => getSince(new Date(get(chat).lastMessageDate))]);
			delegated("click", button, (e) => onClick(e, get(chat)));
			append($$anchor, li);
		});
		reset(ul);
		append($$anchor, ul);
		return pop($$exports);
	}
	delegate(["click"]);
	create_custom_element(ChatsList, { regionId: {} }, [], [], { mode: "open" });
	//#endregion
	//#region src/UserInfiniteList.svelte
	var root_1$5 = /* @__PURE__ */ from_html(`<div class="uc-chat-list-error" role="alert"><p>Could not load users.</p> <button type="button" class="t-Button t-Button--small">Retry</button></div>`);
	var root_2$6 = /* @__PURE__ */ from_html(`<p class="uc-chat-empty-hint svelte-agcjz4">No users found</p>`);
	var root_4$2 = /* @__PURE__ */ from_html(`<button type="button" class="uc-chat-button"><div class="uc-chat-user svelte-agcjz4"><div class="uc-chat-avatar svelte-agcjz4"><!></div> <span class="svelte-agcjz4"> </span></div></button>`);
	var root$5 = /* @__PURE__ */ from_html(`<div class="uc-chat-user-list svelte-agcjz4"><!></div>`);
	var $$css$6 = {
		hash: "svelte-agcjz4",
		code: ".uc-chat-user-list.svelte-agcjz4 {height:100%;}\n\n  /* .uc-chat-list-error now lives in styles.css: MessageInfiniteList carried an\n     identical copy of it. */.uc-chat-empty-hint.svelte-agcjz4 {padding:var(--uc-chat-space-4);margin:0;text-align:center;font-size:0.85em;color:var(--uc-chat-component-text-muted-color);}\n\n  /* The same row as the conversation list opposite it, one step down: a\n     single-line row gets the smaller tile, a two-line row the larger one. The\n     two lists used to declare the identical 3.2em avatar and then look wrong in\n     one of the two places. */.uc-chat-user.svelte-agcjz4 {--uc-chat-avatar-size: 2em;padding:var(--uc-chat-space-2);border-bottom:1px solid var(--uc-chat-component-inner-border-color);display:flex;align-items:center;gap:var(--uc-chat-space-2);}\n\n  /* The row itself stays at 1em so the avatar token above means what it says;\n     only the label is scaled. Scaling the row instead — as the transcript used\n     to — silently resizes the tile and every padding measured in em with it. */.uc-chat-user.svelte-agcjz4 > span:where(.svelte-agcjz4) {font-size:0.9em;font-weight:500;color:var(--uc-chat-component-text-title-color);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}.uc-chat-avatar.svelte-agcjz4 {height:var(--uc-chat-avatar-size);width:var(--uc-chat-avatar-size);border-radius:var(--uc-chat-radius-md);overflow:hidden;flex-shrink:0;}"
	};
	function UserInfiniteList($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css$6);
		const showChats = prop($$props, "showChats", 7), createGroup = prop($$props, "createGroup", 7), regionId = prop($$props, "regionId", 7);
		const chatState = getChatState();
		/**
		* @type {userListObject[]}
		*/
		let items = /* @__PURE__ */ state(proxy([]));
		let loading = false;
		let error = /* @__PURE__ */ state(false);
		let offset = 0;
		let search = "";
		let allFetched = false;
		let listEl = null;
		let spinner = null;
		const pageSize = 50;
		onMount(async () => {
			console.log("onInitialize userInfiniteList");
			await fetchNextRows();
		});
		function setLoading() {
			loading = true;
			spinner = apex.util.showSpinner(listEl);
		}
		function loadingFinished() {
			loading = false;
			if (spinner) spinner.remove();
		}
		async function fetchNextRows() {
			if (loading || allFetched) {
				console.log("fetchNextRows", {
					loading,
					allFetched
				});
				return;
			}
			set(error, false);
			setLoading();
			offset = get(items).length;
			let res;
			try {
				res = await getUserList({
					offset,
					search,
					regionId: regionId()
				});
			} catch (e) {
				debugError("getUserList failed", e);
				set(error, true);
				return;
			} finally {
				loadingFinished();
			}
			if (res.users.length === 0) {
				allFetched = true;
				return;
			}
			if (res.users.length < pageSize) allFetched = true;
			get(items).push(...res.users);
			console.log("items", snapshot(get(items)));
		}
		function retry() {
			set(error, false);
			fetchNextRows();
		}
		function handleClick(data) {
			if (createGroup()) {
				if (chatState.newGroupUsers.find((user) => user.userId === data.userId)) return;
				chatState.newGroupUsers.push({
					userId: data.userId,
					userName: data.userName,
					userImgUrl: data.userImgUrl
				});
			} else {
				openChat(chatState, {
					roomId: data.roomId || `newChat-${Date.now()}`,
					roomName: data.userName,
					userIds: [data.userId]
				});
				showChats()();
			}
		}
		var $$exports = {
			get showChats() {
				return showChats();
			},
			set showChats($$value) {
				showChats($$value);
				flushSync();
			},
			get createGroup() {
				return createGroup();
			},
			set createGroup($$value) {
				createGroup($$value);
				flushSync();
			},
			get regionId() {
				return regionId();
			},
			set regionId($$value) {
				regionId($$value);
				flushSync();
			}
		};
		var div = root$5();
		var node = child(div);
		var consequent = ($$anchor) => {
			var div_1 = root_1$5();
			var button = sibling(child(div_1), 2);
			reset(div_1);
			delegated("click", button, retry);
			append($$anchor, div_1);
		};
		var consequent_1 = ($$anchor) => {
			append($$anchor, root_2$6());
		};
		var alternate = ($$anchor) => {
			{
				const Children = ($$anchor, data = noop) => {
					var button_1 = root_4$2();
					var div_2 = child(button_1);
					var div_3 = child(div_2);
					Avatar(child(div_3), {
						get img() {
							return data().userImgUrl;
						},
						get name() {
							return data().userName;
						}
					});
					reset(div_3);
					var span = sibling(div_3, 2);
					var text = child(span, true);
					reset(span);
					reset(div_2);
					reset(button_1);
					template_effect(() => set_text(text, data().userName));
					delegated("click", button_1, () => handleClick(data()));
					append($$anchor, button_1);
				};
				VirtualList($$anchor, {
					get items() {
						return get(items);
					},
					height: "100%",
					onScrollEnd: fetchNextRows,
					Children,
					$$slots: { Children: true }
				});
			}
		};
		if_block(node, ($$render) => {
			if (get(error) && get(items).length === 0) $$render(consequent);
			else if (get(items).length === 0) $$render(consequent_1, 1);
			else $$render(alternate, -1);
		});
		reset(div);
		bind_this(div, ($$value) => listEl = $$value, () => listEl);
		append($$anchor, div);
		return pop($$exports);
	}
	delegate(["click"]);
	create_custom_element(UserInfiniteList, {
		showChats: {},
		createGroup: {},
		regionId: {}
	}, [], [], { mode: "open" });
	//#endregion
	//#region src/LeftPane.svelte
	var root_1$4 = /* @__PURE__ */ from_html(`<button type="button" class="t-Button t-Button--small t-Button--noLabel t-Button--icon t-Button--simple" title="Back to chats" aria-label="Back to chats"><span aria-hidden="true" class="t-Icon fa fa-arrow-left"></span></button>`);
	var root_2$5 = /* @__PURE__ */ from_html(`<button type="button" class="t-Button t-Button--small t-Button--noLabel t-Button--icon t-Button--simple" title="New chat" aria-label="New chat"><span aria-hidden="true" class="t-Icon fa fa-plus"></span></button>`);
	var root_3$4 = /* @__PURE__ */ from_html(`<div class="uc-chat-left-pane-create-group-chat svelte-mnfk6k"><label for="createGroupChat" class="svelte-mnfk6k">Create group</label> <input type="checkbox" name="createGroupChat" id="createGroupChat"/></div>`);
	var root$4 = /* @__PURE__ */ from_html(`<div class="uc-chat-left-pane"><div class="uc-chat-left-pane-header svelte-mnfk6k"><div class="uc-chat-left-pane-header-left"><!></div> <div class="uc-chat-left-pane-header-right svelte-mnfk6k"><!></div></div> <div class="uc-chat-left-pane-body svelte-mnfk6k"><!></div></div>`);
	var $$css$5 = {
		hash: "svelte-mnfk6k",
		code: "\n  /* Same bar as the transcript header opposite it, so the two halves of the\n     region line up. It used to be a 48px band filled with\n     --uc-chat-footer-background-color — the transcript-backdrop token pressed\n     into service as chrome, which is why the left header and the right header\n     were different colours in every theme. */.uc-chat-left-pane-header.svelte-mnfk6k {display:flex;align-items:center;justify-content:space-between;background-color:var(--uc-chat-surface-background-color);border-bottom:1px solid var(--uc-chat-component-border-color);padding:var(--uc-chat-space-1) var(--uc-chat-space-2);min-height:var(--uc-chat-bar-height);flex:0 0 auto;& .uc-chat-left-pane-header-right:where(.svelte-mnfk6k) {display:flex;align-items:center;justify-content:flex-end;}}.uc-chat-left-pane-body.svelte-mnfk6k {overflow-y:auto;height:100%;background-color:var(--uc-chat-surface-background-color);}.uc-chat-left-pane-create-group-chat.svelte-mnfk6k {align-items:center;gap:var(--uc-chat-space-2);& label:where(.svelte-mnfk6k) {font-size:0.85em;\n      /* 300 is not a weight most UI fonts ship; it either snapped back to\n         regular or rendered spindly in a theme that does ship it. */font-weight:400;margin:0;}}"
	};
	function LeftPane($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css$5);
		let regionId = prop($$props, "regionId", 7);
		const chatState = getChatState();
		let createGroup = /* @__PURE__ */ state(false);
		function showChats() {
			chatState.leftPaneMode = LP_MODE_CHATS;
		}
		function handleGroupToggle(e) {
			if (e.target.checked) {
				chatState.newGroupUsers = [];
				chatState.rightPaneMode = RP_MODE_NEW_GROUP;
				set(createGroup, true);
			} else {
				chatState.rightPaneMode = RP_MODE_CHAT;
				set(createGroup, false);
			}
		}
		var $$exports = {
			get regionId() {
				return regionId();
			},
			set regionId($$value) {
				regionId($$value);
				flushSync();
			}
		};
		var div = root$4();
		var div_1 = child(div);
		var div_2 = child(div_1);
		var node = child(div_2);
		var consequent = ($$anchor) => {
			var button = root_1$4();
			delegated("click", button, () => {
				apex.event.trigger(`#${regionId()}`, EVENT_RP_SHOW_CHAT, {});
				chatState.leftPaneMode = LP_MODE_CHATS;
				chatState.rightPaneMode = RP_MODE_CHAT;
			});
			append($$anchor, button);
		};
		if_block(node, ($$render) => {
			if (chatState.leftPaneMode !== "chats") $$render(consequent);
		});
		reset(div_2);
		var div_3 = sibling(div_2, 2);
		var node_1 = child(div_3);
		var consequent_1 = ($$anchor) => {
			var button_1 = root_2$5();
			delegated("click", button_1, () => {
				chatState.leftPaneMode = LP_MODE_NEW_CHAT;
			});
			append($$anchor, button_1);
		};
		var consequent_2 = ($$anchor) => {
			var div_4 = root_3$4();
			var input = sibling(child(div_4), 2);
			reset(div_4);
			delegated("change", input, handleGroupToggle);
			append($$anchor, div_4);
		};
		if_block(node_1, ($$render) => {
			if (chatState.leftPaneMode === "chats") $$render(consequent_1);
			else if (chatState.leftPaneMode === "newChat") $$render(consequent_2, 1);
		});
		reset(div_3);
		reset(div_1);
		var div_5 = sibling(div_1, 2);
		var node_2 = child(div_5);
		var consequent_3 = ($$anchor) => {
			ChatsList($$anchor, { get regionId() {
				return regionId();
			} });
		};
		var consequent_4 = ($$anchor) => {
			UserInfiniteList($$anchor, {
				get regionId() {
					return regionId();
				},
				showChats,
				get createGroup() {
					return get(createGroup);
				}
			});
		};
		if_block(node_2, ($$render) => {
			if (chatState.leftPaneMode === "chats") $$render(consequent_3);
			else if (chatState.leftPaneMode === "newChat") $$render(consequent_4, 1);
		});
		reset(div_5);
		reset(div);
		append($$anchor, div);
		return pop($$exports);
	}
	delegate(["click", "change"]);
	create_custom_element(LeftPane, { regionId: {} }, [], [], { mode: "open" });
	//#endregion
	//#region src/CreateGroup.svelte
	var root_1$3 = /* @__PURE__ */ from_html(`<span class="uc-chat-field-error svelte-1tpej72">Group name is required</span>`);
	var root_2$4 = /* @__PURE__ */ from_html(`<span class="uc-chat-field-error svelte-1tpej72">Please add at least one user</span>`);
	var root_3$3 = /* @__PURE__ */ from_html(`<li class="svelte-1tpej72"><span> </span> <button type="button" title="Remove user" aria-label="Remove user" class="t-Button t-Button--noLabel t-Button--icon t-Button--simple t-Button--small"><span aria-hidden="true" class="t-Icon fa fa-times"></span></button></li>`);
	var root_5$1 = /* @__PURE__ */ from_html(`<p class="uc-chat-field-error svelte-1tpej72"> </p>`);
	var root$3 = /* @__PURE__ */ from_html(`<div class="uc-chat-right-pane-new-group svelte-1tpej72"><h3 class="svelte-1tpej72">New Group</h3> <div class="uc-chat-right-pane-group-name svelte-1tpej72"><label for="groupName" class="svelte-1tpej72">Group Name</label> <input type="text" placeholder="" rows="1" id="groupName" required=""/> <!></div> <div class="uc-chat-right-pane-group-members svelte-1tpej72"><p class="svelte-1tpej72">Add users by clicking them on the left pane.</p> <!> <ul class="uc-chat-right-pane-group-list svelte-1tpej72"></ul></div> <div class="uc-chat-right-pane-create-group svelte-1tpej72"><!> <!> <button type="button" class="t-Button t-Button--hot svelte-1tpej72">Create Group</button></div></div>`);
	var $$css$4 = {
		hash: "svelte-1tpej72",
		code: ".uc-chat-right-pane-new-group.svelte-1tpej72 {padding:var(--uc-chat-space-4);background-color:var(--uc-chat-surface-background-color);max-height:100%;min-height:100%;display:flex;flex-direction:column;& h3:where(.svelte-1tpej72) {margin:0;font-size:1em;font-weight:600;color:var(--uc-chat-component-text-title-color);}}.uc-chat-right-pane-group-name.svelte-1tpej72 {margin-top:var(--uc-chat-space-4);& label:where(.svelte-1tpej72) {display:block;font-size:0.85em;\n      /* 300 is not a weight most UI fonts ship. */font-weight:500;margin-bottom:var(--uc-chat-space-1);color:var(--uc-chat-component-text-title-color);}}.uc-chat-right-pane-group-members.svelte-1tpej72 {margin-top:var(--uc-chat-space-4);flex-shrink:1;flex-grow:1;overflow-y:auto;& p:where(.svelte-1tpej72) {font-size:0.85em;font-weight:400;margin:0 0 var(--uc-chat-space-2);color:var(--uc-chat-component-text-muted-color);}}.uc-chat-right-pane-group-list.svelte-1tpej72 {list-style:none;padding:0;margin:0;& li:where(.svelte-1tpej72) {display:flex;justify-content:space-between;align-items:center;gap:var(--uc-chat-space-2);padding:var(--uc-chat-space-1) 0;font-size:0.9em;border-bottom:1px solid var(--uc-chat-component-inner-border-color);}}.uc-chat-right-pane-create-group.svelte-1tpej72 {min-height:2em;padding-top:var(--uc-chat-space-3);& button:where(.svelte-1tpej72) {float:right;}}\n\n  /* Was three copies of an inline style=\"color: var(--uc-chat-danger-color)\". */.uc-chat-field-error.svelte-1tpej72 {display:block;margin-top:var(--uc-chat-space-1);font-size:0.8em;color:var(--uc-chat-danger-color);}.uc-input-error.svelte-1tpej72 {border-color:var(--uc-chat-danger-color);}"
	};
	function CreateGroup($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css$4);
		const regionId = prop($$props, "regionId", 7);
		const chatState = getChatState();
		let groupName = /* @__PURE__ */ state("");
		let groupNameEmpty = /* @__PURE__ */ state(false);
		let usersEmpty = /* @__PURE__ */ state(false);
		let loading = /* @__PURE__ */ state(false);
		let errorMsg = /* @__PURE__ */ state("");
		function removeUser(userId) {
			chatState.newGroupUsers = chatState.newGroupUsers.filter((u) => u.userId !== userId);
		}
		async function clickCreateGroup() {
			set(groupNameEmpty, get(groupName) === "");
			const newGroupUsers = chatState.newGroupUsers;
			set(usersEmpty, newGroupUsers.length === 0);
			if (get(groupNameEmpty) || get(usersEmpty)) return;
			set(loading, true);
			try {
				const newRoomId = await createGroup({
					groupName: get(groupName),
					userIds: newGroupUsers.map((u) => u.userId),
					regionId: regionId()
				});
				set(loading, false);
				chatState.leftPaneMode = LP_MODE_CHATS;
				chatState.rightPaneMode = RP_MODE_CHAT;
				openChat(chatState, {
					roomId: newRoomId,
					userIds: newGroupUsers.map((u) => u.userId),
					roomName: get(groupName)
				});
			} catch (e) {
				set(loading, false);
				set(errorMsg, "Failed to create group. Please contact an administrator.");
				return;
			}
		}
		var $$exports = {
			get regionId() {
				return regionId();
			},
			set regionId($$value) {
				regionId($$value);
				flushSync();
			}
		};
		var div = root$3();
		var div_1 = sibling(child(div), 2);
		var input = sibling(child(div_1), 2);
		remove_input_defaults(input);
		let classes;
		var node = sibling(input, 2);
		var consequent = ($$anchor) => {
			append($$anchor, root_1$3());
		};
		if_block(node, ($$render) => {
			if (get(groupNameEmpty)) $$render(consequent);
		});
		reset(div_1);
		var div_2 = sibling(div_1, 2);
		var node_1 = sibling(child(div_2), 2);
		var consequent_1 = ($$anchor) => {
			append($$anchor, root_2$4());
		};
		if_block(node_1, ($$render) => {
			if (get(usersEmpty)) $$render(consequent_1);
		});
		var ul = sibling(node_1, 2);
		each(ul, 21, () => chatState.newGroupUsers, index, ($$anchor, user) => {
			var li = root_3$3();
			var span_2 = child(li);
			var text = child(span_2, true);
			reset(span_2);
			var button = sibling(span_2, 2);
			reset(li);
			template_effect(() => set_text(text, get(user).userName));
			delegated("click", button, () => removeUser(get(user).userId));
			append($$anchor, li);
		});
		reset(ul);
		reset(div_2);
		var div_3 = sibling(div_2, 2);
		var node_2 = child(div_3);
		var consequent_2 = ($$anchor) => {
			Spinner($$anchor, {});
		};
		if_block(node_2, ($$render) => {
			if (get(loading)) $$render(consequent_2);
		});
		var node_3 = sibling(node_2, 2);
		var consequent_3 = ($$anchor) => {
			var p = root_5$1();
			var text_1 = child(p, true);
			reset(p);
			template_effect(() => set_text(text_1, get(errorMsg)));
			append($$anchor, p);
		};
		if_block(node_3, ($$render) => {
			if (get(errorMsg)) $$render(consequent_3);
		});
		var button_1 = sibling(node_3, 2);
		reset(div_3);
		reset(div);
		template_effect(() => classes = set_class(input, 1, "apex-item-text svelte-1tpej72", null, classes, { "uc-input-error": get(groupNameEmpty) }));
		bind_value(input, () => get(groupName), ($$value) => set(groupName, $$value));
		delegated("click", button_1, clickCreateGroup);
		append($$anchor, div);
		return pop($$exports);
	}
	delegate(["click"]);
	create_custom_element(CreateGroup, { regionId: {} }, [], [], { mode: "open" });
	//#endregion
	//#region src/MessageInfiniteList.svelte
	var messageItem = ($$anchor, item = noop) => {
		var div = root_1$2();
		var node = child(div);
		var consequent = ($$anchor) => {
			var div_1 = root_2$3();
			var span = child(div_1);
			var text = child(span, true);
			reset(span);
			reset(div_1);
			template_effect(($0) => set_text(text, $0), [() => formatDateString(item().messageDate)]);
			append($$anchor, div_1);
		};
		if_block(node, ($$render) => {
			if (item().isDifferentDay) $$render(consequent);
		});
		var node_1 = sibling(node, 2);
		var consequent_1 = ($$anchor) => {
			var div_2 = root_3$2();
			var div_3 = child(div_2);
			Avatar(child(div_3), {
				get img() {
					return item().userImgUrl;
				},
				get name() {
					return item().userName;
				}
			});
			reset(div_3);
			var div_4 = sibling(div_3, 2);
			var div_5 = child(div_4);
			var span_1 = child(div_5);
			var text_1 = child(span_1, true);
			reset(span_1);
			var span_2 = sibling(span_1, 4);
			var text_2 = child(span_2, true);
			reset(span_2);
			reset(div_5);
			var div_6 = sibling(div_5, 2);
			var span_3 = child(div_6);
			var text_3 = child(span_3, true);
			reset(span_3);
			reset(div_6);
			reset(div_4);
			reset(div_2);
			template_effect(() => {
				set_attribute(div_2, "data-id", item().messageId);
				set_text(text_1, item().userName);
				set_text(text_2, item().formatteTime);
				set_text(text_3, item().messageText);
			});
			append($$anchor, div_2);
		};
		var alternate = ($$anchor) => {
			var div_7 = root_4$1();
			var div_8 = child(div_7);
			var span_4 = child(div_8);
			var text_4 = child(span_4, true);
			reset(span_4);
			reset(div_8);
			reset(div_7);
			template_effect(() => set_text(text_4, item().messageText));
			append($$anchor, div_7);
		};
		if_block(node_1, ($$render) => {
			if (item().userId !== "_*#SYSTEM#*_") $$render(consequent_1);
			else $$render(alternate, -1);
		});
		reset(div);
		append($$anchor, div);
	};
	var root_2$3 = /* @__PURE__ */ from_html(`<div class="uc-chat-day-info"><span class="uc-chat-day-info-text"> </span></div>`);
	var root_3$2 = /* @__PURE__ */ from_html(`<div class="uc-chat-message"><div class="uc-chat-message-avatar"><!></div> <div class="uc-chat-message-content"><div class="uc-chat-message-byline"><span> </span> <span class="uc-chat-bullet">•</span> <span class="uc-chat-time"> </span></div> <div class="uc-chat-message-text"><span> </span></div></div></div>`);
	var root_4$1 = /* @__PURE__ */ from_html(`<div class="uc-chat-system-message"><div><span> </span></div></div>`);
	var root_1$2 = /* @__PURE__ */ from_html(`<div class="uc-chat-message-view svelte-isx43a"><!> <!></div>`);
	var root_6 = /* @__PURE__ */ from_html(`<div class="uc-chat-list-error" role="alert"><p>Could not load messages.</p> <button type="button" class="t-Button t-Button--small">Retry</button></div>`);
	var root$2 = /* @__PURE__ */ from_html(`<!> <!> <!>`, 1);
	var $$css$3 = {
		hash: "svelte-isx43a",
		code: "\n  /* The message row itself, the day divider, the system line and the load-error\n     block all live in styles.css now: channel chat rendered the very same\n     markup and had grown its own near-copy of every rule here, so the two modes\n     had already drifted (different avatar radii, different divider spacing).\n     What is left below is the per-row wrapper, which is genuinely local. */.uc-chat-message-view.svelte-isx43a {display:flex;flex-direction:column;padding:var(--uc-chat-space-1) var(--uc-chat-space-3);}"
	};
	function MessageInfiniteList($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css$3);
		let roomId = prop($$props, "roomId", 7), regionId = prop($$props, "regionId", 7);
		/**
		* @type {messageObject[]}
		*/
		let items = /* @__PURE__ */ state(proxy([]));
		let loading = /* @__PURE__ */ state(true);
		let loadError = /* @__PURE__ */ state(false);
		let oldRoomId = -1;
		let allFetched = false;
		const persists = 50;
		function handleMessageSent(e, data) {
			debugInfo(`MessageInfiniteList event: ${EVENT_MESSAGE_SENT}`, {
				event: e,
				data
			});
			if (data?.roomId === roomId()) handleNewMessage();
		}
		async function handleNewMessage() {
			await fetchNextRows(false);
			scrollToLastMessage();
		}
		function resetItems() {
			set(items, [], true);
			allFetched = false;
		}
		function getIsDifferentDay(index, newItems) {
			if (index === 0) {
				if (get(items).length === 0) return false;
				return isDifferentDay(newItems[index].messageDate, get(items)[get(items).length - 1].messageDate);
			}
			return isDifferentDay(newItems[index].messageDate, newItems[index - 1].messageDate);
		}
		async function fetchNextRows(older = true) {
			if (older && allFetched) return;
			set(loadError, false);
			set(loading, true);
			const lastMessageId = older ? get(items)[0]?.messageId : get(items)[get(items).length - 1]?.messageId;
			let res;
			try {
				res = await fetchMessages({
					roomId: roomId(),
					lastMessageId,
					olderOrNewer: older ? "older" : "newer",
					regionId: regionId()
				});
			} catch (e) {
				debugError("MessageInfiniteList fetch failed", e);
				set(loadError, true);
				set(loading, false);
				return;
			}
			set(loading, false);
			if (older) {
				if (res.messages.length === 0) {
					allFetched = true;
					return;
				}
				if (res.messages.length < persists) allFetched = true;
			} else if (res.messages.length === 0) return;
			const msgs = res.messages.reverse();
			for (let i = 0; i < msgs.length; i++) {
				const msg = msgs[i];
				msg.formatteTime = formatTimeString(msg.messageDate);
				msg.isDifferentDay = getIsDifferentDay(i, msgs);
			}
			if (older) set(items, [...msgs, ...get(items)], true);
			else set(items, [...get(items), ...msgs], true);
			debugTrace("MessageInfiniteList", {
				items: get(items),
				allFetched,
				older
			});
			set(loading, false);
		}
		function scrollToLastMessage() {
			if (!get(items) || get(items).length === 0) return;
			setTimeout(() => {
				const viewport = document.querySelector(`#${regionId()} .uc-chat-message-body svelte-virtual-list-viewport`);
				if (!viewport) return;
				debugTrace("scrolling to bottom");
				viewport.scrollTo({
					top: viewport.scrollHeight,
					behavior: "smooth"
				});
			}, 50);
		}
		async function roomIdChanged(newRoomId) {
			debugTrace("roomIdChanged", {
				newRoomId,
				oldRoomId,
				items: get(items)
			});
			oldRoomId = newRoomId;
			resetItems();
			await fetchNextRows();
			debugTrace("roomIdChanged", {
				newRoomId,
				items: get(items)
			});
			scrollToLastMessage();
		}
		user_effect(() => {
			if (roomId() && oldRoomId !== roomId()) roomIdChanged(roomId());
		});
		function handleScrollTop() {
			fetchNextRows(true);
		}
		function retryLoad() {
			set(loadError, false);
			fetchNextRows(true);
		}
		function handleAmsNewMessage(e, data) {
			debugInfo("uc-chat-new-message event", {
				e,
				data
			});
			if (data?.amsdata?.roomId === roomId()) {
				debugInfo("is current room, refresh...");
				handleNewMessage();
			}
		}
		onMount(() => {
			set(loading, true);
			apex.jQuery(`#${regionId()}`).on(EVENT_MESSAGE_SENT, handleMessageSent);
			apex.jQuery(document).on("uc-chat-new-message", handleAmsNewMessage);
		});
		onDestroy(() => {
			apex.jQuery(`#${regionId()}`).off(EVENT_MESSAGE_SENT, handleMessageSent);
			apex.jQuery(document).off("uc-chat-new-message", handleAmsNewMessage);
		});
		var $$exports = {
			get roomId() {
				return roomId();
			},
			set roomId($$value) {
				roomId($$value);
				flushSync();
			},
			get regionId() {
				return regionId();
			},
			set regionId($$value) {
				regionId($$value);
				flushSync();
			}
		};
		var fragment = root$2();
		var node_3 = first_child(fragment);
		var consequent_2 = ($$anchor) => {
			Spinner($$anchor, {});
		};
		if_block(node_3, ($$render) => {
			if (get(loading) && get(items).length === 0) $$render(consequent_2);
		});
		var node_4 = sibling(node_3, 2);
		var consequent_3 = ($$anchor) => {
			var div_9 = root_6();
			var button = sibling(child(div_9), 2);
			reset(div_9);
			delegated("click", button, retryLoad);
			append($$anchor, div_9);
		};
		if_block(node_4, ($$render) => {
			if (get(loadError) && get(items).length === 0) $$render(consequent_3);
		});
		var node_5 = sibling(node_4, 2);
		var consequent_4 = ($$anchor) => {
			VirtualList($$anchor, {
				get items() {
					return get(items);
				},
				height: "100%",
				onScrollTop: handleScrollTop,
				get Children() {
					return messageItem;
				}
			});
		};
		if_block(node_5, ($$render) => {
			if (get(items).length > 0) $$render(consequent_4);
		});
		append($$anchor, fragment);
		return pop($$exports);
	}
	delegate(["click"]);
	create_custom_element(MessageInfiniteList, {
		roomId: {},
		regionId: {}
	}, [], [], { mode: "open" });
	//#endregion
	//#region src/RightPane.svelte
	var root_2$2 = /* @__PURE__ */ from_html(`<div class="uc-chat-message-view svelte-9ord3r"><div class="uc-chat-message-header svelte-9ord3r"><button type="button" title="back to chat list" aria-label="back to chat list" class="uc-chat-back-btn t-Button t-Button--small t-Button--noLabel t-Button--icon t-Button--simple svelte-9ord3r"><span aria-hidden="true" class="t-Icon fa fa-chevron-left"></span></button> <h2 class="uc-chat-name svelte-9ord3r"> </h2></div> <div class="uc-chat-message-body svelte-9ord3r"><!></div> <div class="uc-chat-message-footer svelte-9ord3r"><!></div></div>`);
	var root_3$1 = /* @__PURE__ */ from_html(`<div class="uc-chat-empty-state svelte-9ord3r"><span aria-hidden="true" class="fa fa-comments-o uc-chat-empty-icon svelte-9ord3r"></span> <p class="uc-chat-empty-title svelte-9ord3r">No chat selected</p> <p class="uc-chat-empty-hint svelte-9ord3r">Choose a conversation from the list to start messaging</p></div>`);
	var root_5 = /* @__PURE__ */ from_html(`<p> </p>`);
	var root$1 = /* @__PURE__ */ from_html(`<div class="uc-chat-right-pane svelte-9ord3r"><!></div>`);
	var $$css$2 = {
		hash: "svelte-9ord3r",
		code: ".uc-chat-right-pane.svelte-9ord3r {min-height:0;height:100%;border-left:1px solid var(--uc-chat-component-border-color);overflow:hidden; /* Keep this to prevent the pane itself from scrolling */\n    /* Was font-size: 1.1em, which put the two halves of the same region on two\n       different type scales — and, because every measurement here is in em,\n       silently made each padding, avatar and radius on this side 10% larger\n       than the identical token on the left. The transcript sets its own text\n       size per element instead. */display:flex;flex-direction:column;\n    /* The pane owns its surface so the translucent canvas tint below has\n       something predictable to composite over. */background-color:var(--uc-chat-surface-background-color);}.uc-chat-message-view.svelte-9ord3r {display:flex;flex-direction:column;max-height:100%;height:100%;min-height:0;\n    /* Translucent: one step recessed from the surface, following whichever\n       direction the host theme tints in. --uc-chat-footer-background-color was\n       a flat #f2f2f2 that also served as hover feedback and as the left-pane\n       header fill. */background-color:var(--uc-chat-canvas-background-color);overflow:hidden; /* Add this to prevent the view from scrolling */}\n\n  /* Header and footer are chrome: they sit on the plain surface and are divided\n     from the transcript by a hairline, the way an APEX region header is. The\n     old drop shadows smudged onto the canvas and read as a rendering artefact\n     rather than a boundary. */.uc-chat-message-header.svelte-9ord3r {background-color:var(--uc-chat-surface-background-color);min-height:var(--uc-chat-bar-height);border-bottom:1px solid var(--uc-chat-component-border-color);display:flex;align-items:center;gap:var(--uc-chat-space-2);padding:var(--uc-chat-space-1) var(--uc-chat-space-3);flex:0 0 auto;z-index:1; /* Add this to ensure the header stays on top */}.uc-chat-message-body.svelte-9ord3r {flex:1;min-height:0; /* This is important to allow flex items to shrink below content size */overflow-y:auto; /* This enables scrolling */position:relative; /* Add this */}.uc-chat-message-footer.svelte-9ord3r {display:flex;flex-direction:column;justify-content:center;background-color:var(--uc-chat-surface-background-color);border-top:1px solid var(--uc-chat-component-border-color);flex:0 0 auto;z-index:1; /* Add this to ensure the footer stays on top */\n    /* Was a fixed 50px, which clipped the composer as soon as the textarea grew\n       past one line (it is allowed to reach 10em). */min-height:var(--uc-chat-bar-height);}.uc-chat-name.svelte-9ord3r {margin:0;padding:0;font-weight:600;color:var(--uc-chat-component-text-title-color);font-size:1em;letter-spacing:0.01em;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}.uc-chat-back-btn.svelte-9ord3r {\n    /* The header is a flex row with a gap now; the extra margin double-spaced\n       it away from the title. */flex:0 0 auto;}.uc-chat-empty-state.svelte-9ord3r {display:flex;flex-direction:column;align-items:center;justify-content:center;height:100%;gap:var(--uc-chat-space-2);color:var(--uc-chat-component-text-muted-color);padding:var(--uc-chat-space-4);text-align:center;}.uc-chat-empty-icon.svelte-9ord3r {font-size:2.5em;\n    /* Was opacity: 0.4 on top of an already-muted colour, which in a dark theme\n       faded the glyph almost into the backdrop. */color:var(--uc-chat-component-text-muted-color);opacity:0.55;margin-bottom:var(--uc-chat-space-1);}.uc-chat-empty-title.svelte-9ord3r {margin:0;font-size:1em;font-weight:600;color:var(--uc-chat-component-text-title-color);}.uc-chat-empty-hint.svelte-9ord3r {margin:0;font-size:0.85em;max-width:24em;}"
	};
	function RightPane($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css$2);
		let regionId = prop($$props, "regionId", 7);
		const chatState = getChatState();
		function clearChat() {
			chatState.currChat.roomId = void 0;
			chatState.currChat.roomName = void 0;
			chatState.currChat.userIds = [];
		}
		var $$exports = {
			get regionId() {
				return regionId();
			},
			set regionId($$value) {
				regionId($$value);
				flushSync();
			}
		};
		var div = root$1();
		var node = child(div);
		var consequent_1 = ($$anchor) => {
			var fragment = comment();
			var node_1 = first_child(fragment);
			var consequent = ($$anchor) => {
				var div_1 = root_2$2();
				var div_2 = child(div_1);
				var button = child(div_2);
				var h2 = sibling(button, 2);
				var text = child(h2, true);
				reset(h2);
				reset(div_2);
				var div_3 = sibling(div_2, 2);
				MessageInfiniteList(child(div_3), {
					get regionId() {
						return regionId();
					},
					get roomId() {
						return chatState.currChat.roomId;
					}
				});
				reset(div_3);
				var div_4 = sibling(div_3, 2);
				MessageComposer(child(div_4), {
					get roomId() {
						return chatState.currChat.roomId;
					},
					get regionId() {
						return regionId();
					},
					get userIds() {
						return chatState.currChat.userIds;
					},
					get roomName() {
						return chatState.currChat.roomName;
					}
				});
				reset(div_4);
				reset(div_1);
				template_effect(() => set_text(text, chatState.currChat.roomName));
				delegated("click", button, clearChat);
				append($$anchor, div_1);
			};
			var alternate = ($$anchor) => {
				append($$anchor, root_3$1());
			};
			if_block(node_1, ($$render) => {
				if (chatState.currChat.roomId) $$render(consequent);
				else $$render(alternate, -1);
			});
			append($$anchor, fragment);
		};
		var consequent_2 = ($$anchor) => {
			CreateGroup($$anchor, { get regionId() {
				return regionId();
			} });
		};
		var alternate_1 = ($$anchor) => {
			var p = root_5();
			var text_1 = child(p);
			reset(p);
			template_effect(() => set_text(text_1, `Unhandled rightPaneMode: ${chatState.rightPaneMode ?? ""}`));
			append($$anchor, p);
		};
		if_block(node, ($$render) => {
			if (chatState.rightPaneMode === "chat") $$render(consequent_1);
			else if (chatState.rightPaneMode === "newGroup") $$render(consequent_2, 1);
			else $$render(alternate_1, -1);
		});
		reset(div);
		append($$anchor, div);
		return pop($$exports);
	}
	delegate(["click"]);
	create_custom_element(RightPane, { regionId: {} }, [], [], { mode: "open" });
	//#endregion
	//#region src/ChatWindow.svelte
	var root_1$1 = /* @__PURE__ */ from_html(`<div class="uc-chat-window svelte-obuvmp"><!></div>`);
	var root_2$1 = /* @__PURE__ */ from_html(`<div class="uc-chat-window svelte-obuvmp"><!></div>`);
	var root_3 = /* @__PURE__ */ from_html(`<div><div class="uc-chat-window-header svelte-obuvmp"><h2 class="svelte-obuvmp">Chat</h2> <button type="button" class="t-Button t-Button--icon" title="Close chat" aria-label="Close chat"><span aria-hidden="true" class="t-Icon fa fa-close"></span></button></div> <div class="uc-chat-window-body svelte-obuvmp"><!> <!></div></div>`);
	var root_4 = /* @__PURE__ */ from_html(`<div class="uc-chat-window svelte-obuvmp"><div><!> <!></div></div>`);
	var $$css$1 = {
		hash: "svelte-obuvmp",
		code: ".uc-chat-window.svelte-obuvmp {width:100%;height:100%;max-height:100%;padding:0;display:flex;flex-direction:column;container-type:inline-size;overflow:hidden;}.uc-chat-window-header.svelte-obuvmp {display:flex;justify-content:space-between;align-items:center;padding-block-end:var(--jui-dialog-titlebar-padding-y, 12px);padding-block-start:var(--jui-dialog-titlebar-padding-y, 12px);padding-inline-end:var(--jui-dialog-titlebar-padding-x, 16px);padding-inline-start:var(--jui-dialog-titlebar-padding-x, 16px);border-bottom:1px solid var(--uc-chat-component-border-color);flex-shrink:0;& > h2:where(.svelte-obuvmp) {font-size:1.2em;}}.uc-chat-window-header.svelte-obuvmp > h2:where(.svelte-obuvmp) {margin:0;}.uc-chat-window-body.svelte-obuvmp {flex:1;max-height:100%;height:100%;min-height:0;}\n\n  /* responsive behaviour */\n\n  /* initially hide right pane on small screens */.uc-chat-right-pane {display:none;}\n\n  /* if chat open show right pane */.uc-chat-open .uc-chat-left-pane {display:none;}.uc-chat-open .uc-chat-right-pane {display:block;}\n\n  /* create group currently not supported on mobile */.uc-chat-left-pane-create-group-chat {display:none;}\n\n  @container (min-width: 500px) {.uc-chat-window-body.svelte-obuvmp {display:grid;grid-template-columns:1fr 2fr;}.uc-chat-left-pane {min-height:0;max-height:inherit;overflow:hidden;display:flex;flex-direction:column;}.uc-chat-right-pane {display:block;}\n        .uc-chat-open .uc-chat-right-pane,\n        .uc-chat-open .uc-chat-left-pane\n       {display:block;}.uc-chat-back-btn {display:none;}.uc-chat-left-pane-create-group-chat {display:flex;}\n  }"
	};
	function ChatWindow($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css$1);
		let hideDialog = prop($$props, "hideDialog", 7), regionId = prop($$props, "regionId", 7), displayMode = prop($$props, "displayMode", 7), chatMode = prop($$props, "chatMode", 7, "user"), singleChatMode = prop($$props, "singleChatMode", 7), agentCode = prop($$props, "agentCode", 7, ""), agentVersion = prop($$props, "agentVersion", 7, null), sessionId = prop($$props, "sessionId", 7, ""), showReasoning = prop($$props, "showReasoning", 7, false), showTools = prop($$props, "showTools", 7, false), showMetadata = prop($$props, "showMetadata", 7, false), showDebug = prop($$props, "showDebug", 7, false), suggestedPrompts = prop($$props, "suggestedPrompts", 7, ""), headerTitle = prop($$props, "headerTitle", 7, ""), avatarIcon = prop($$props, "avatarIcon", 7, ""), welcomeMessage = prop($$props, "welcomeMessage", 7, ""), minHeight = prop($$props, "minHeight", 7, ""), thinkingAnimation = prop($$props, "thinkingAnimation", 7, ""), thinkingDetail = prop($$props, "thinkingDetail", 7, ""), autoTitle = prop($$props, "autoTitle", 7, false), collectFeedback = prop($$props, "collectFeedback", 7, false);
		let chatState;
		if (chatMode() !== "ai" && chatMode() !== "channel") chatState = createChatState();
		var $$exports = {
			get hideDialog() {
				return hideDialog();
			},
			set hideDialog($$value) {
				hideDialog($$value);
				flushSync();
			},
			get regionId() {
				return regionId();
			},
			set regionId($$value) {
				regionId($$value);
				flushSync();
			},
			get displayMode() {
				return displayMode();
			},
			set displayMode($$value) {
				displayMode($$value);
				flushSync();
			},
			get chatMode() {
				return chatMode();
			},
			set chatMode($$value = "user") {
				chatMode($$value);
				flushSync();
			},
			get singleChatMode() {
				return singleChatMode();
			},
			set singleChatMode($$value) {
				singleChatMode($$value);
				flushSync();
			},
			get agentCode() {
				return agentCode();
			},
			set agentCode($$value = "") {
				agentCode($$value);
				flushSync();
			},
			get agentVersion() {
				return agentVersion();
			},
			set agentVersion($$value = null) {
				agentVersion($$value);
				flushSync();
			},
			get sessionId() {
				return sessionId();
			},
			set sessionId($$value = "") {
				sessionId($$value);
				flushSync();
			},
			get showReasoning() {
				return showReasoning();
			},
			set showReasoning($$value = false) {
				showReasoning($$value);
				flushSync();
			},
			get showTools() {
				return showTools();
			},
			set showTools($$value = false) {
				showTools($$value);
				flushSync();
			},
			get showMetadata() {
				return showMetadata();
			},
			set showMetadata($$value = false) {
				showMetadata($$value);
				flushSync();
			},
			get showDebug() {
				return showDebug();
			},
			set showDebug($$value = false) {
				showDebug($$value);
				flushSync();
			},
			get suggestedPrompts() {
				return suggestedPrompts();
			},
			set suggestedPrompts($$value = "") {
				suggestedPrompts($$value);
				flushSync();
			},
			get headerTitle() {
				return headerTitle();
			},
			set headerTitle($$value = "") {
				headerTitle($$value);
				flushSync();
			},
			get avatarIcon() {
				return avatarIcon();
			},
			set avatarIcon($$value = "") {
				avatarIcon($$value);
				flushSync();
			},
			get welcomeMessage() {
				return welcomeMessage();
			},
			set welcomeMessage($$value = "") {
				welcomeMessage($$value);
				flushSync();
			},
			get minHeight() {
				return minHeight();
			},
			set minHeight($$value = "") {
				minHeight($$value);
				flushSync();
			},
			get thinkingAnimation() {
				return thinkingAnimation();
			},
			set thinkingAnimation($$value = "") {
				thinkingAnimation($$value);
				flushSync();
			},
			get thinkingDetail() {
				return thinkingDetail();
			},
			set thinkingDetail($$value = "") {
				thinkingDetail($$value);
				flushSync();
			},
			get autoTitle() {
				return autoTitle();
			},
			set autoTitle($$value = false) {
				autoTitle($$value);
				flushSync();
			},
			get collectFeedback() {
				return collectFeedback();
			},
			set collectFeedback($$value = false) {
				collectFeedback($$value);
				flushSync();
			}
		};
		var fragment = comment();
		var node = first_child(fragment);
		var consequent = ($$anchor) => {
			var div = root_1$1();
			ChannelChatPane(child(div), { get regionId() {
				return regionId();
			} });
			reset(div);
			append($$anchor, div);
		};
		var consequent_1 = ($$anchor) => {
			var div_1 = root_2$1();
			AiChatPane(child(div_1), {
				get regionId() {
					return regionId();
				},
				get agentCode() {
					return agentCode();
				},
				get agentVersion() {
					return agentVersion();
				},
				get sessionId() {
					return sessionId();
				},
				get showReasoning() {
					return showReasoning();
				},
				get showTools() {
					return showTools();
				},
				get showMetadata() {
					return showMetadata();
				},
				get showDebug() {
					return showDebug();
				},
				get suggestedPrompts() {
					return suggestedPrompts();
				},
				get headerTitle() {
					return headerTitle();
				},
				get avatarIcon() {
					return avatarIcon();
				},
				get welcomeMessage() {
					return welcomeMessage();
				},
				get minHeight() {
					return minHeight();
				},
				get thinkingAnimation() {
					return thinkingAnimation();
				},
				get thinkingDetail() {
					return thinkingDetail();
				},
				get autoTitle() {
					return autoTitle();
				},
				get collectFeedback() {
					return collectFeedback();
				},
				get hideDialog() {
					return hideDialog();
				}
			});
			reset(div_1);
			append($$anchor, div_1);
		};
		var consequent_2 = ($$anchor) => {
			var div_2 = root_3();
			let classes;
			var div_3 = child(div_2);
			var button = sibling(child(div_3), 2);
			reset(div_3);
			var div_4 = sibling(div_3, 2);
			var node_3 = child(div_4);
			LeftPane(node_3, { get regionId() {
				return regionId();
			} });
			RightPane(sibling(node_3, 2), { get regionId() {
				return regionId();
			} });
			reset(div_4);
			reset(div_2);
			template_effect(() => classes = set_class(div_2, 1, "uc-chat-window svelte-obuvmp", null, classes, {
				"uc-chat-open": !!chatState.currChat.roomId,
				"uc-chat-single-mode": singleChatMode()
			}));
			delegated("click", button, function(...$$args) {
				hideDialog()?.apply(this, $$args);
			});
			append($$anchor, div_2);
		};
		var alternate = ($$anchor) => {
			var div_5 = root_4();
			var div_6 = child(div_5);
			let classes_1;
			var node_5 = child(div_6);
			LeftPane(node_5, { get regionId() {
				return regionId();
			} });
			RightPane(sibling(node_5, 2), { get regionId() {
				return regionId();
			} });
			reset(div_6);
			reset(div_5);
			template_effect(() => classes_1 = set_class(div_6, 1, "uc-chat-window-body svelte-obuvmp", null, classes_1, {
				"uc-chat-open": !!chatState.currChat.roomId,
				"uc-chat-single-mode": singleChatMode()
			}));
			append($$anchor, div_5);
		};
		if_block(node, ($$render) => {
			if (chatMode() === "channel") $$render(consequent);
			else if (chatMode() === "ai") $$render(consequent_1, 1);
			else if (displayMode() === "dialog") $$render(consequent_2, 2);
			else $$render(alternate, -1);
		});
		append($$anchor, fragment);
		return pop($$exports);
	}
	delegate(["click"]);
	create_custom_element(ChatWindow, {
		hideDialog: {},
		regionId: {},
		displayMode: {},
		chatMode: {},
		singleChatMode: {},
		agentCode: {},
		agentVersion: {},
		sessionId: {},
		showReasoning: {},
		showTools: {},
		showMetadata: {},
		showDebug: {},
		suggestedPrompts: {},
		headerTitle: {},
		avatarIcon: {},
		welcomeMessage: {},
		minHeight: {},
		thinkingAnimation: {},
		thinkingDetail: {},
		autoTitle: {},
		collectFeedback: {}
	}, [], [], { mode: "open" });
	//#endregion
	//#region src/lib/uc-ams.js
	(() => {
		var __create = Object.create;
		var __defProp = Object.defineProperty;
		var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
		var __getOwnPropNames = Object.getOwnPropertyNames;
		var __getProtoOf = Object.getPrototypeOf;
		var __hasOwnProp = Object.prototype.hasOwnProperty;
		var __commonJS = (cb, mod) => function __require() {
			return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
		};
		var __copyProps = (to, from, except, desc) => {
			if (from && typeof from === "object" || typeof from === "function") {
				for (let key of __getOwnPropNames(from)) if (!__hasOwnProp.call(to, key) && key !== except) __defProp(to, key, {
					get: () => from[key],
					enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable
				});
			}
			return to;
		};
		var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", {
			value: mod,
			enumerable: true
		}) : target, mod));
		var import_socket_io_min = __toESM(__commonJS({ "src/socket.io.min.js"(exports, module) {
			(function(t, e) {
				"object" == typeof exports && "undefined" != typeof module ? module.exports = e() : "function" == typeof define && define.amd ? define(e) : (t = "undefined" != typeof globalThis ? globalThis : t || self).io = e();
			})(exports, function() {
				"use strict";
				function t(e2) {
					return t = "function" == typeof Symbol && "symbol" == typeof Symbol.iterator ? function(t2) {
						return typeof t2;
					} : function(t2) {
						return t2 && "function" == typeof Symbol && t2.constructor === Symbol && t2 !== Symbol.prototype ? "symbol" : typeof t2;
					}, t(e2);
				}
				function e(t2, e2) {
					if (!(t2 instanceof e2)) throw new TypeError("Cannot call a class as a function");
				}
				function n(t2, e2) {
					for (var n2 = 0; n2 < e2.length; n2++) {
						var r2 = e2[n2];
						r2.enumerable = r2.enumerable || false, r2.configurable = true, "value" in r2 && (r2.writable = true), Object.defineProperty(t2, r2.key, r2);
					}
				}
				function r(t2, e2, r2) {
					return e2 && n(t2.prototype, e2), r2 && n(t2, r2), Object.defineProperty(t2, "prototype", { writable: false }), t2;
				}
				function i() {
					return i = Object.assign ? Object.assign.bind() : function(t2) {
						for (var e2 = 1; e2 < arguments.length; e2++) {
							var n2 = arguments[e2];
							for (var r2 in n2) Object.prototype.hasOwnProperty.call(n2, r2) && (t2[r2] = n2[r2]);
						}
						return t2;
					}, i.apply(this, arguments);
				}
				function o(t2, e2) {
					if ("function" != typeof e2 && null !== e2) throw new TypeError("Super expression must either be null or a function");
					t2.prototype = Object.create(e2 && e2.prototype, { constructor: {
						value: t2,
						writable: true,
						configurable: true
					} }), Object.defineProperty(t2, "prototype", { writable: false }), e2 && a(t2, e2);
				}
				function s(t2) {
					return s = Object.setPrototypeOf ? Object.getPrototypeOf.bind() : function(t3) {
						return t3.__proto__ || Object.getPrototypeOf(t3);
					}, s(t2);
				}
				function a(t2, e2) {
					return a = Object.setPrototypeOf ? Object.setPrototypeOf.bind() : function(t3, e3) {
						return t3.__proto__ = e3, t3;
					}, a(t2, e2);
				}
				function c() {
					if ("undefined" == typeof Reflect || !Reflect.construct) return false;
					if (Reflect.construct.sham) return false;
					if ("function" == typeof Proxy) return true;
					try {
						return Boolean.prototype.valueOf.call(Reflect.construct(Boolean, [], function() {})), true;
					} catch (t2) {
						return false;
					}
				}
				function u(t2, e2, n2) {
					return u = c() ? Reflect.construct.bind() : function(t3, e3, n3) {
						var r2 = [null];
						r2.push.apply(r2, e3);
						var i2 = new (Function.bind.apply(t3, r2))();
						return n3 && a(i2, n3.prototype), i2;
					}, u.apply(null, arguments);
				}
				function h(t2) {
					var e2 = "function" == typeof Map ? /* @__PURE__ */ new Map() : void 0;
					return h = function(t3) {
						if (null === t3 || (n2 = t3, -1 === Function.toString.call(n2).indexOf("[native code]"))) return t3;
						var n2;
						if ("function" != typeof t3) throw new TypeError("Super expression must either be null or a function");
						if (void 0 !== e2) {
							if (e2.has(t3)) return e2.get(t3);
							e2.set(t3, r2);
						}
						function r2() {
							return u(t3, arguments, s(this).constructor);
						}
						return r2.prototype = Object.create(t3.prototype, { constructor: {
							value: r2,
							enumerable: false,
							writable: true,
							configurable: true
						} }), a(r2, t3);
					}, h(t2);
				}
				function f(t2) {
					if (void 0 === t2) throw new ReferenceError("this hasn't been initialised - super() hasn't been called");
					return t2;
				}
				function l(t2, e2) {
					if (e2 && ("object" == typeof e2 || "function" == typeof e2)) return e2;
					if (void 0 !== e2) throw new TypeError("Derived constructors may only return object or undefined");
					return f(t2);
				}
				function p(t2) {
					var e2 = c();
					return function() {
						var n2, r2 = s(t2);
						if (e2) {
							var i2 = s(this).constructor;
							n2 = Reflect.construct(r2, arguments, i2);
						} else n2 = r2.apply(this, arguments);
						return l(this, n2);
					};
				}
				function d(t2, e2) {
					for (; !Object.prototype.hasOwnProperty.call(t2, e2) && null !== (t2 = s(t2)););
					return t2;
				}
				function y() {
					return y = "undefined" != typeof Reflect && Reflect.get ? Reflect.get.bind() : function(t2, e2, n2) {
						var r2 = d(t2, e2);
						if (r2) {
							var i2 = Object.getOwnPropertyDescriptor(r2, e2);
							return i2.get ? i2.get.call(arguments.length < 3 ? t2 : n2) : i2.value;
						}
					}, y.apply(this, arguments);
				}
				function v(t2, e2) {
					(null == e2 || e2 > t2.length) && (e2 = t2.length);
					for (var n2 = 0, r2 = new Array(e2); n2 < e2; n2++) r2[n2] = t2[n2];
					return r2;
				}
				function g(t2, e2) {
					var n2 = "undefined" != typeof Symbol && t2[Symbol.iterator] || t2["@@iterator"];
					if (!n2) {
						if (Array.isArray(t2) || (n2 = function(t3, e3) {
							if (t3) {
								if ("string" == typeof t3) return v(t3, e3);
								var n3 = Object.prototype.toString.call(t3).slice(8, -1);
								return "Object" === n3 && t3.constructor && (n3 = t3.constructor.name), "Map" === n3 || "Set" === n3 ? Array.from(t3) : "Arguments" === n3 || /^(?:Ui|I)nt(?:8|16|32)(?:Clamped)?Array$/.test(n3) ? v(t3, e3) : void 0;
							}
						}(t2)) || e2 && t2 && "number" == typeof t2.length) {
							n2 && (t2 = n2);
							var r2 = 0, i2 = function() {};
							return {
								s: i2,
								n: function() {
									return r2 >= t2.length ? { done: true } : {
										done: false,
										value: t2[r2++]
									};
								},
								e: function(t3) {
									throw t3;
								},
								f: i2
							};
						}
						throw new TypeError("Invalid attempt to iterate non-iterable instance.\nIn order to be iterable, non-array objects must have a [Symbol.iterator]() method.");
					}
					var o2, s2 = true, a2 = false;
					return {
						s: function() {
							n2 = n2.call(t2);
						},
						n: function() {
							var t3 = n2.next();
							return s2 = t3.done, t3;
						},
						e: function(t3) {
							a2 = true, o2 = t3;
						},
						f: function() {
							try {
								s2 || null == n2.return || n2.return();
							} finally {
								if (a2) throw o2;
							}
						}
					};
				}
				var m = /* @__PURE__ */ Object.create(null);
				m.open = "0", m.close = "1", m.ping = "2", m.pong = "3", m.message = "4", m.upgrade = "5", m.noop = "6";
				var k = /* @__PURE__ */ Object.create(null);
				Object.keys(m).forEach(function(t2) {
					k[m[t2]] = t2;
				});
				for (var b = {
					type: "error",
					data: "parser error"
				}, w = "function" == typeof Blob || "undefined" != typeof Blob && "[object BlobConstructor]" === Object.prototype.toString.call(Blob), _ = "function" == typeof ArrayBuffer, E = function(t2, e2, n2) {
					var r2, i2 = t2.type, o2 = t2.data;
					return w && o2 instanceof Blob ? e2 ? n2(o2) : O(o2, n2) : _ && (o2 instanceof ArrayBuffer || (r2 = o2, "function" == typeof ArrayBuffer.isView ? ArrayBuffer.isView(r2) : r2 && r2.buffer instanceof ArrayBuffer)) ? e2 ? n2(o2) : O(new Blob([o2]), n2) : n2(m[i2] + (o2 || ""));
				}, O = function(t2, e2) {
					var n2 = new FileReader();
					return n2.onload = function() {
						var t3 = n2.result.split(",")[1];
						e2("b" + t3);
					}, n2.readAsDataURL(t2);
				}, A = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/", R = "undefined" == typeof Uint8Array ? [] : new Uint8Array(256), T = 0; T < A.length; T++) R[A.charCodeAt(T)] = T;
				var C = "function" == typeof ArrayBuffer, B = function(t2, e2) {
					if ("string" != typeof t2) return {
						type: "message",
						data: N(t2, e2)
					};
					var n2 = t2.charAt(0);
					return "b" === n2 ? {
						type: "message",
						data: S(t2.substring(1), e2)
					} : k[n2] ? t2.length > 1 ? {
						type: k[n2],
						data: t2.substring(1)
					} : { type: k[n2] } : b;
				}, S = function(t2, e2) {
					if (C) return N(function(t3) {
						var e3, n3, r2, i2, o2, s2 = .75 * t3.length, a2 = t3.length, c2 = 0;
						"=" === t3[t3.length - 1] && (s2--, "=" === t3[t3.length - 2] && s2--);
						var u2 = new ArrayBuffer(s2), h2 = new Uint8Array(u2);
						for (e3 = 0; e3 < a2; e3 += 4) n3 = R[t3.charCodeAt(e3)], r2 = R[t3.charCodeAt(e3 + 1)], i2 = R[t3.charCodeAt(e3 + 2)], o2 = R[t3.charCodeAt(e3 + 3)], h2[c2++] = n3 << 2 | r2 >> 4, h2[c2++] = (15 & r2) << 4 | i2 >> 2, h2[c2++] = (3 & i2) << 6 | 63 & o2;
						return u2;
					}(t2), e2);
					return {
						base64: true,
						data: t2
					};
				}, N = function(t2, e2) {
					return "blob" === e2 && t2 instanceof ArrayBuffer ? new Blob([t2]) : t2;
				}, x = String.fromCharCode(30);
				function L(t2) {
					if (t2) return function(t3) {
						for (var e2 in L.prototype) t3[e2] = L.prototype[e2];
						return t3;
					}(t2);
				}
				L.prototype.on = L.prototype.addEventListener = function(t2, e2) {
					return this._callbacks = this._callbacks || {}, (this._callbacks["$" + t2] = this._callbacks["$" + t2] || []).push(e2), this;
				}, L.prototype.once = function(t2, e2) {
					function n2() {
						this.off(t2, n2), e2.apply(this, arguments);
					}
					return n2.fn = e2, this.on(t2, n2), this;
				}, L.prototype.off = L.prototype.removeListener = L.prototype.removeAllListeners = L.prototype.removeEventListener = function(t2, e2) {
					if (this._callbacks = this._callbacks || {}, 0 == arguments.length) return this._callbacks = {}, this;
					var n2, r2 = this._callbacks["$" + t2];
					if (!r2) return this;
					if (1 == arguments.length) return delete this._callbacks["$" + t2], this;
					for (var i2 = 0; i2 < r2.length; i2++) if ((n2 = r2[i2]) === e2 || n2.fn === e2) {
						r2.splice(i2, 1);
						break;
					}
					return 0 === r2.length && delete this._callbacks["$" + t2], this;
				}, L.prototype.emit = function(t2) {
					this._callbacks = this._callbacks || {};
					for (var e2 = new Array(arguments.length - 1), n2 = this._callbacks["$" + t2], r2 = 1; r2 < arguments.length; r2++) e2[r2 - 1] = arguments[r2];
					if (n2) {
						r2 = 0;
						for (var i2 = (n2 = n2.slice(0)).length; r2 < i2; ++r2) n2[r2].apply(this, e2);
					}
					return this;
				}, L.prototype.emitReserved = L.prototype.emit, L.prototype.listeners = function(t2) {
					return this._callbacks = this._callbacks || {}, this._callbacks["$" + t2] || [];
				}, L.prototype.hasListeners = function(t2) {
					return !!this.listeners(t2).length;
				};
				var P = "undefined" != typeof self ? self : "undefined" != typeof window ? window : Function("return this")();
				function j(t2) {
					for (var e2 = arguments.length, n2 = new Array(e2 > 1 ? e2 - 1 : 0), r2 = 1; r2 < e2; r2++) n2[r2 - 1] = arguments[r2];
					return n2.reduce(function(e3, n3) {
						return t2.hasOwnProperty(n3) && (e3[n3] = t2[n3]), e3;
					}, {});
				}
				var q = P.setTimeout, I = P.clearTimeout;
				function D(t2, e2) {
					e2.useNativeTimers ? (t2.setTimeoutFn = q.bind(P), t2.clearTimeoutFn = I.bind(P)) : (t2.setTimeoutFn = P.setTimeout.bind(P), t2.clearTimeoutFn = P.clearTimeout.bind(P));
				}
				var F, M = function(t2) {
					o(i2, t2);
					var n2 = p(i2);
					function i2(t3, r2, o2) {
						var s2;
						return e(this, i2), (s2 = n2.call(this, t3)).description = r2, s2.context = o2, s2.type = "TransportError", s2;
					}
					return r(i2);
				}(h(Error)), U = function(t2) {
					o(i2, t2);
					var n2 = p(i2);
					function i2(t3) {
						var r2;
						return e(this, i2), (r2 = n2.call(this)).writable = false, D(f(r2), t3), r2.opts = t3, r2.query = t3.query, r2.socket = t3.socket, r2;
					}
					return r(i2, [
						{
							key: "onError",
							value: function(t3, e2, n3) {
								return y(s(i2.prototype), "emitReserved", this).call(this, "error", new M(t3, e2, n3)), this;
							}
						},
						{
							key: "open",
							value: function() {
								return this.readyState = "opening", this.doOpen(), this;
							}
						},
						{
							key: "close",
							value: function() {
								return "opening" !== this.readyState && "open" !== this.readyState || (this.doClose(), this.onClose()), this;
							}
						},
						{
							key: "send",
							value: function(t3) {
								"open" === this.readyState && this.write(t3);
							}
						},
						{
							key: "onOpen",
							value: function() {
								this.readyState = "open", this.writable = true, y(s(i2.prototype), "emitReserved", this).call(this, "open");
							}
						},
						{
							key: "onData",
							value: function(t3) {
								var e2 = B(t3, this.socket.binaryType);
								this.onPacket(e2);
							}
						},
						{
							key: "onPacket",
							value: function(t3) {
								y(s(i2.prototype), "emitReserved", this).call(this, "packet", t3);
							}
						},
						{
							key: "onClose",
							value: function(t3) {
								this.readyState = "closed", y(s(i2.prototype), "emitReserved", this).call(this, "close", t3);
							}
						},
						{
							key: "pause",
							value: function(t3) {}
						}
					]), i2;
				}(L), V = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_".split(""), H = {}, K = 0, Y = 0;
				function z(t2) {
					var e2 = "";
					do
						e2 = V[t2 % 64] + e2, t2 = Math.floor(t2 / 64);
					while (t2 > 0);
					return e2;
				}
				function W() {
					var t2 = z(+/* @__PURE__ */ new Date());
					return t2 !== F ? (K = 0, F = t2) : t2 + "." + z(K++);
				}
				for (; Y < 64; Y++) H[V[Y]] = Y;
				function $(t2) {
					var e2 = "";
					for (var n2 in t2) t2.hasOwnProperty(n2) && (e2.length && (e2 += "&"), e2 += encodeURIComponent(n2) + "=" + encodeURIComponent(t2[n2]));
					return e2;
				}
				function J(t2) {
					for (var e2 = {}, n2 = t2.split("&"), r2 = 0, i2 = n2.length; r2 < i2; r2++) {
						var o2 = n2[r2].split("=");
						e2[decodeURIComponent(o2[0])] = decodeURIComponent(o2[1]);
					}
					return e2;
				}
				var Q = false;
				try {
					Q = "undefined" != typeof XMLHttpRequest && "withCredentials" in new XMLHttpRequest();
				} catch (t2) {}
				var X = Q;
				function G(t2) {
					var e2 = t2.xdomain;
					try {
						if ("undefined" != typeof XMLHttpRequest && (!e2 || X)) return new XMLHttpRequest();
					} catch (t3) {}
					if (!e2) try {
						return new P[["Active"].concat("Object").join("X")]("Microsoft.XMLHTTP");
					} catch (t3) {}
				}
				function Z() {}
				var tt = null != new G({ xdomain: false }).responseType, et = function(t2) {
					o(s2, t2);
					var n2 = p(s2);
					function s2(t3) {
						var r2;
						if (e(this, s2), (r2 = n2.call(this, t3)).polling = false, "undefined" != typeof location) {
							var i2 = "https:" === location.protocol, o2 = location.port;
							o2 || (o2 = i2 ? "443" : "80"), r2.xd = "undefined" != typeof location && t3.hostname !== location.hostname || o2 !== t3.port, r2.xs = t3.secure !== i2;
						}
						var a2 = t3 && t3.forceBase64;
						return r2.supportsBinary = tt && !a2, r2;
					}
					return r(s2, [
						{
							key: "name",
							get: function() {
								return "polling";
							}
						},
						{
							key: "doOpen",
							value: function() {
								this.poll();
							}
						},
						{
							key: "pause",
							value: function(t3) {
								var e2 = this;
								this.readyState = "pausing";
								var n3 = function() {
									e2.readyState = "paused", t3();
								};
								if (this.polling || !this.writable) {
									var r2 = 0;
									this.polling && (r2++, this.once("pollComplete", function() {
										--r2 || n3();
									})), this.writable || (r2++, this.once("drain", function() {
										--r2 || n3();
									}));
								} else n3();
							}
						},
						{
							key: "poll",
							value: function() {
								this.polling = true, this.doPoll(), this.emitReserved("poll");
							}
						},
						{
							key: "onData",
							value: function(t3) {
								var e2 = this;
								(function(t4, e3) {
									for (var n3 = t4.split(x), r2 = [], i2 = 0; i2 < n3.length; i2++) {
										var o2 = B(n3[i2], e3);
										if (r2.push(o2), "error" === o2.type) break;
									}
									return r2;
								})(t3, this.socket.binaryType).forEach(function(t4) {
									if ("opening" === e2.readyState && "open" === t4.type && e2.onOpen(), "close" === t4.type) return e2.onClose({ description: "transport closed by the server" }), false;
									e2.onPacket(t4);
								}), "closed" !== this.readyState && (this.polling = false, this.emitReserved("pollComplete"), "open" === this.readyState && this.poll());
							}
						},
						{
							key: "doClose",
							value: function() {
								var t3 = this, e2 = function() {
									t3.write([{ type: "close" }]);
								};
								"open" === this.readyState ? e2() : this.once("open", e2);
							}
						},
						{
							key: "write",
							value: function(t3) {
								var e2 = this;
								this.writable = false, function(t4, e3) {
									var n3 = t4.length, r2 = new Array(n3), i2 = 0;
									t4.forEach(function(t5, o2) {
										E(t5, false, function(t6) {
											r2[o2] = t6, ++i2 === n3 && e3(r2.join(x));
										});
									});
								}(t3, function(t4) {
									e2.doWrite(t4, function() {
										e2.writable = true, e2.emitReserved("drain");
									});
								});
							}
						},
						{
							key: "uri",
							value: function() {
								var t3 = this.query || {}, e2 = this.opts.secure ? "https" : "http", n3 = "";
								false !== this.opts.timestampRequests && (t3[this.opts.timestampParam] = W()), this.supportsBinary || t3.sid || (t3.b64 = 1), this.opts.port && ("https" === e2 && 443 !== Number(this.opts.port) || "http" === e2 && 80 !== Number(this.opts.port)) && (n3 = ":" + this.opts.port);
								var r2 = $(t3);
								return e2 + "://" + (-1 !== this.opts.hostname.indexOf(":") ? "[" + this.opts.hostname + "]" : this.opts.hostname) + n3 + this.opts.path + (r2.length ? "?" + r2 : "");
							}
						},
						{
							key: "request",
							value: function() {
								var t3 = arguments.length > 0 && void 0 !== arguments[0] ? arguments[0] : {};
								return i(t3, {
									xd: this.xd,
									xs: this.xs
								}, this.opts), new nt(this.uri(), t3);
							}
						},
						{
							key: "doWrite",
							value: function(t3, e2) {
								var n3 = this, r2 = this.request({
									method: "POST",
									data: t3
								});
								r2.on("success", e2), r2.on("error", function(t4, e3) {
									n3.onError("xhr post error", t4, e3);
								});
							}
						},
						{
							key: "doPoll",
							value: function() {
								var t3 = this, e2 = this.request();
								e2.on("data", this.onData.bind(this)), e2.on("error", function(e3, n3) {
									t3.onError("xhr poll error", e3, n3);
								}), this.pollXhr = e2;
							}
						}
					]), s2;
				}(U), nt = function(t2) {
					o(i2, t2);
					var n2 = p(i2);
					function i2(t3, r2) {
						var o2;
						return e(this, i2), D(f(o2 = n2.call(this)), r2), o2.opts = r2, o2.method = r2.method || "GET", o2.uri = t3, o2.async = false !== r2.async, o2.data = void 0 !== r2.data ? r2.data : null, o2.create(), o2;
					}
					return r(i2, [
						{
							key: "create",
							value: function() {
								var t3 = this, e2 = j(this.opts, "agent", "pfx", "key", "passphrase", "cert", "ca", "ciphers", "rejectUnauthorized", "autoUnref");
								e2.xdomain = !!this.opts.xd, e2.xscheme = !!this.opts.xs;
								var n3 = this.xhr = new G(e2);
								try {
									n3.open(this.method, this.uri, this.async);
									try {
										if (this.opts.extraHeaders) for (var r2 in n3.setDisableHeaderCheck && n3.setDisableHeaderCheck(true), this.opts.extraHeaders) this.opts.extraHeaders.hasOwnProperty(r2) && n3.setRequestHeader(r2, this.opts.extraHeaders[r2]);
									} catch (t4) {}
									if ("POST" === this.method) try {
										n3.setRequestHeader("Content-type", "text/plain;charset=UTF-8");
									} catch (t4) {}
									try {
										n3.setRequestHeader("Accept", "*/*");
									} catch (t4) {}
									"withCredentials" in n3 && (n3.withCredentials = this.opts.withCredentials), this.opts.requestTimeout && (n3.timeout = this.opts.requestTimeout), n3.onreadystatechange = function() {
										4 === n3.readyState && (200 === n3.status || 1223 === n3.status ? t3.onLoad() : t3.setTimeoutFn(function() {
											t3.onError("number" == typeof n3.status ? n3.status : 0);
										}, 0));
									}, n3.send(this.data);
								} catch (e3) {
									this.setTimeoutFn(function() {
										t3.onError(e3);
									}, 0);
									return;
								}
								"undefined" != typeof document && (this.index = i2.requestsCount++, i2.requests[this.index] = this);
							}
						},
						{
							key: "onError",
							value: function(t3) {
								this.emitReserved("error", t3, this.xhr), this.cleanup(true);
							}
						},
						{
							key: "cleanup",
							value: function(t3) {
								if (void 0 !== this.xhr && null !== this.xhr) {
									if (this.xhr.onreadystatechange = Z, t3) try {
										this.xhr.abort();
									} catch (t4) {}
									"undefined" != typeof document && delete i2.requests[this.index], this.xhr = null;
								}
							}
						},
						{
							key: "onLoad",
							value: function() {
								var t3 = this.xhr.responseText;
								null !== t3 && (this.emitReserved("data", t3), this.emitReserved("success"), this.cleanup());
							}
						},
						{
							key: "abort",
							value: function() {
								this.cleanup();
							}
						}
					]), i2;
				}(L);
				if (nt.requestsCount = 0, nt.requests = {}, "undefined" != typeof document) {
					if ("function" == typeof attachEvent) attachEvent("onunload", rt);
					else if ("function" == typeof addEventListener) addEventListener("onpagehide" in P ? "pagehide" : "unload", rt, false);
				}
				function rt() {
					for (var t2 in nt.requests) nt.requests.hasOwnProperty(t2) && nt.requests[t2].abort();
				}
				var it = "function" == typeof Promise && "function" == typeof Promise.resolve ? function(t2) {
					return Promise.resolve().then(t2);
				} : function(t2, e2) {
					return e2(t2, 0);
				}, ot = P.WebSocket || P.MozWebSocket, st = "undefined" != typeof navigator && "string" == typeof navigator.product && "reactnative" === navigator.product.toLowerCase(), ct = {
					websocket: function(t2) {
						o(i2, t2);
						var n2 = p(i2);
						function i2(t3) {
							var r2;
							return e(this, i2), (r2 = n2.call(this, t3)).supportsBinary = !t3.forceBase64, r2;
						}
						return r(i2, [
							{
								key: "name",
								get: function() {
									return "websocket";
								}
							},
							{
								key: "doOpen",
								value: function() {
									if (this.check()) {
										var t3 = this.uri(), e2 = this.opts.protocols, n3 = st ? {} : j(this.opts, "agent", "perMessageDeflate", "pfx", "key", "passphrase", "cert", "ca", "ciphers", "rejectUnauthorized", "localAddress", "protocolVersion", "origin", "maxPayload", "family", "checkServerIdentity");
										this.opts.extraHeaders && (n3.headers = this.opts.extraHeaders);
										try {
											this.ws = st ? new ot(t3, e2, n3) : e2 ? new ot(t3, e2) : new ot(t3);
										} catch (t4) {
											return this.emitReserved("error", t4);
										}
										this.ws.binaryType = this.socket.binaryType || "arraybuffer", this.addEventListeners();
									}
								}
							},
							{
								key: "addEventListeners",
								value: function() {
									var t3 = this;
									this.ws.onopen = function() {
										t3.opts.autoUnref && t3.ws._socket.unref(), t3.onOpen();
									}, this.ws.onclose = function(e2) {
										return t3.onClose({
											description: "websocket connection closed",
											context: e2
										});
									}, this.ws.onmessage = function(e2) {
										return t3.onData(e2.data);
									}, this.ws.onerror = function(e2) {
										return t3.onError("websocket error", e2);
									};
								}
							},
							{
								key: "write",
								value: function(t3) {
									var e2 = this;
									this.writable = false;
									for (var n3 = function(n4) {
										var r3 = t3[n4], i3 = n4 === t3.length - 1;
										E(r3, e2.supportsBinary, function(t4) {
											try {
												e2.ws.send(t4);
											} catch (t5) {}
											i3 && it(function() {
												e2.writable = true, e2.emitReserved("drain");
											}, e2.setTimeoutFn);
										});
									}, r2 = 0; r2 < t3.length; r2++) n3(r2);
								}
							},
							{
								key: "doClose",
								value: function() {
									void 0 !== this.ws && (this.ws.close(), this.ws = null);
								}
							},
							{
								key: "uri",
								value: function() {
									var t3 = this.query || {}, e2 = this.opts.secure ? "wss" : "ws", n3 = "";
									this.opts.port && ("wss" === e2 && 443 !== Number(this.opts.port) || "ws" === e2 && 80 !== Number(this.opts.port)) && (n3 = ":" + this.opts.port), this.opts.timestampRequests && (t3[this.opts.timestampParam] = W()), this.supportsBinary || (t3.b64 = 1);
									var r2 = $(t3);
									return e2 + "://" + (-1 !== this.opts.hostname.indexOf(":") ? "[" + this.opts.hostname + "]" : this.opts.hostname) + n3 + this.opts.path + (r2.length ? "?" + r2 : "");
								}
							},
							{
								key: "check",
								value: function() {
									return !!ot;
								}
							}
						]), i2;
					}(U),
					polling: et
				}, ut = /^(?:(?![^:@\/?#]+:[^:@\/]*@)(http|https|ws|wss):\/\/)?((?:(([^:@\/?#]*)(?::([^:@\/?#]*))?)?@)?((?:[a-f0-9]{0,4}:){2,7}[a-f0-9]{0,4}|[^:\/?#]*)(?::(\d*))?)(((\/(?:[^?#](?![^?#\/]*\.[^?#\/.]+(?:[?#]|$)))*\/?)?([^?#\/]*))(?:\?([^#]*))?(?:#(.*))?)/, ht = [
					"source",
					"protocol",
					"authority",
					"userInfo",
					"user",
					"password",
					"host",
					"port",
					"relative",
					"path",
					"directory",
					"file",
					"query",
					"anchor"
				];
				function ft(t2) {
					var e2 = t2, n2 = t2.indexOf("["), r2 = t2.indexOf("]");
					-1 != n2 && -1 != r2 && (t2 = t2.substring(0, n2) + t2.substring(n2, r2).replace(/:/g, ";") + t2.substring(r2, t2.length));
					for (var i2, o2, s2 = ut.exec(t2 || ""), a2 = {}, c2 = 14; c2--;) a2[ht[c2]] = s2[c2] || "";
					return -1 != n2 && -1 != r2 && (a2.source = e2, a2.host = a2.host.substring(1, a2.host.length - 1).replace(/;/g, ":"), a2.authority = a2.authority.replace("[", "").replace("]", "").replace(/;/g, ":"), a2.ipv6uri = true), a2.pathNames = function(t3, e3) {
						var r3 = e3.replace(/\/{2,9}/g, "/").split("/");
						"/" != e3.slice(0, 1) && 0 !== e3.length || r3.splice(0, 1);
						"/" == e3.slice(-1) && r3.splice(r3.length - 1, 1);
						return r3;
					}(0, a2.path), a2.queryKey = (i2 = a2.query, o2 = {}, i2.replace(/(?:^|&)([^&=]*)=?([^&]*)/g, function(t3, e3, n3) {
						e3 && (o2[e3] = n3);
					}), o2), a2;
				}
				var lt = function(n2) {
					o(a2, n2);
					var s2 = p(a2);
					function a2(n3) {
						var r2, o2 = arguments.length > 1 && void 0 !== arguments[1] ? arguments[1] : {};
						return e(this, a2), (r2 = s2.call(this)).writeBuffer = [], n3 && "object" === t(n3) && (o2 = n3, n3 = null), n3 ? (n3 = ft(n3), o2.hostname = n3.host, o2.secure = "https" === n3.protocol || "wss" === n3.protocol, o2.port = n3.port, n3.query && (o2.query = n3.query)) : o2.host && (o2.hostname = ft(o2.host).host), D(f(r2), o2), r2.secure = null != o2.secure ? o2.secure : "undefined" != typeof location && "https:" === location.protocol, o2.hostname && !o2.port && (o2.port = r2.secure ? "443" : "80"), r2.hostname = o2.hostname || ("undefined" != typeof location ? location.hostname : "localhost"), r2.port = o2.port || ("undefined" != typeof location && location.port ? location.port : r2.secure ? "443" : "80"), r2.transports = o2.transports || ["polling", "websocket"], r2.writeBuffer = [], r2.prevBufferLen = 0, r2.opts = i({
							path: "/engine.io",
							agent: false,
							withCredentials: false,
							upgrade: true,
							timestampParam: "t",
							rememberUpgrade: false,
							addTrailingSlash: true,
							rejectUnauthorized: true,
							perMessageDeflate: { threshold: 1024 },
							transportOptions: {},
							closeOnBeforeunload: true
						}, o2), r2.opts.path = r2.opts.path.replace(/\/$/, "") + (r2.opts.addTrailingSlash ? "/" : ""), "string" == typeof r2.opts.query && (r2.opts.query = J(r2.opts.query)), r2.id = null, r2.upgrades = null, r2.pingInterval = null, r2.pingTimeout = null, r2.pingTimeoutTimer = null, "function" == typeof addEventListener && (r2.opts.closeOnBeforeunload && (r2.beforeunloadEventListener = function() {
							r2.transport && (r2.transport.removeAllListeners(), r2.transport.close());
						}, addEventListener("beforeunload", r2.beforeunloadEventListener, false)), "localhost" !== r2.hostname && (r2.offlineEventListener = function() {
							r2.onClose("transport close", { description: "network connection lost" });
						}, addEventListener("offline", r2.offlineEventListener, false))), r2.open(), r2;
					}
					return r(a2, [
						{
							key: "createTransport",
							value: function(t2) {
								var e2 = i({}, this.opts.query);
								e2.EIO = 4, e2.transport = t2, this.id && (e2.sid = this.id);
								var n3 = i({}, this.opts.transportOptions[t2], this.opts, {
									query: e2,
									socket: this,
									hostname: this.hostname,
									secure: this.secure,
									port: this.port
								});
								return new ct[t2](n3);
							}
						},
						{
							key: "open",
							value: function() {
								var t2, e2 = this;
								if (this.opts.rememberUpgrade && a2.priorWebsocketSuccess && -1 !== this.transports.indexOf("websocket")) t2 = "websocket";
								else {
									if (0 === this.transports.length) return void this.setTimeoutFn(function() {
										e2.emitReserved("error", "No transports available");
									}, 0);
									t2 = this.transports[0];
								}
								this.readyState = "opening";
								try {
									t2 = this.createTransport(t2);
								} catch (t3) {
									this.transports.shift(), this.open();
									return;
								}
								t2.open(), this.setTransport(t2);
							}
						},
						{
							key: "setTransport",
							value: function(t2) {
								var e2 = this;
								this.transport && this.transport.removeAllListeners(), this.transport = t2, t2.on("drain", this.onDrain.bind(this)).on("packet", this.onPacket.bind(this)).on("error", this.onError.bind(this)).on("close", function(t3) {
									return e2.onClose("transport close", t3);
								});
							}
						},
						{
							key: "probe",
							value: function(t2) {
								var e2 = this, n3 = this.createTransport(t2), r2 = false;
								a2.priorWebsocketSuccess = false;
								var i2 = function() {
									r2 || (n3.send([{
										type: "ping",
										data: "probe"
									}]), n3.once("packet", function(t3) {
										if (!r2) if ("pong" === t3.type && "probe" === t3.data) {
											if (e2.upgrading = true, e2.emitReserved("upgrading", n3), !n3) return;
											a2.priorWebsocketSuccess = "websocket" === n3.name, e2.transport.pause(function() {
												r2 || "closed" !== e2.readyState && (f2(), e2.setTransport(n3), n3.send([{ type: "upgrade" }]), e2.emitReserved("upgrade", n3), n3 = null, e2.upgrading = false, e2.flush());
											});
										} else {
											var i3 = /* @__PURE__ */ new Error("probe error");
											i3.transport = n3.name, e2.emitReserved("upgradeError", i3);
										}
									}));
								};
								function o2() {
									r2 || (r2 = true, f2(), n3.close(), n3 = null);
								}
								var s3 = function(t3) {
									var r3 = /* @__PURE__ */ new Error("probe error: " + t3);
									r3.transport = n3.name, o2(), e2.emitReserved("upgradeError", r3);
								};
								function c2() {
									s3("transport closed");
								}
								function u2() {
									s3("socket closed");
								}
								function h2(t3) {
									n3 && t3.name !== n3.name && o2();
								}
								var f2 = function() {
									n3.removeListener("open", i2), n3.removeListener("error", s3), n3.removeListener("close", c2), e2.off("close", u2), e2.off("upgrading", h2);
								};
								n3.once("open", i2), n3.once("error", s3), n3.once("close", c2), this.once("close", u2), this.once("upgrading", h2), n3.open();
							}
						},
						{
							key: "onOpen",
							value: function() {
								if (this.readyState = "open", a2.priorWebsocketSuccess = "websocket" === this.transport.name, this.emitReserved("open"), this.flush(), "open" === this.readyState && this.opts.upgrade) for (var t2 = 0, e2 = this.upgrades.length; t2 < e2; t2++) this.probe(this.upgrades[t2]);
							}
						},
						{
							key: "onPacket",
							value: function(t2) {
								if ("opening" === this.readyState || "open" === this.readyState || "closing" === this.readyState) switch (this.emitReserved("packet", t2), this.emitReserved("heartbeat"), t2.type) {
									case "open":
										this.onHandshake(JSON.parse(t2.data));
										break;
									case "ping":
										this.resetPingTimeout(), this.sendPacket("pong"), this.emitReserved("ping"), this.emitReserved("pong");
										break;
									case "error":
										var e2 = /* @__PURE__ */ new Error("server error");
										e2.code = t2.data, this.onError(e2);
										break;
									case "message": this.emitReserved("data", t2.data), this.emitReserved("message", t2.data);
								}
							}
						},
						{
							key: "onHandshake",
							value: function(t2) {
								this.emitReserved("handshake", t2), this.id = t2.sid, this.transport.query.sid = t2.sid, this.upgrades = this.filterUpgrades(t2.upgrades), this.pingInterval = t2.pingInterval, this.pingTimeout = t2.pingTimeout, this.maxPayload = t2.maxPayload, this.onOpen(), "closed" !== this.readyState && this.resetPingTimeout();
							}
						},
						{
							key: "resetPingTimeout",
							value: function() {
								var t2 = this;
								this.clearTimeoutFn(this.pingTimeoutTimer), this.pingTimeoutTimer = this.setTimeoutFn(function() {
									t2.onClose("ping timeout");
								}, this.pingInterval + this.pingTimeout), this.opts.autoUnref && this.pingTimeoutTimer.unref();
							}
						},
						{
							key: "onDrain",
							value: function() {
								this.writeBuffer.splice(0, this.prevBufferLen), this.prevBufferLen = 0, 0 === this.writeBuffer.length ? this.emitReserved("drain") : this.flush();
							}
						},
						{
							key: "flush",
							value: function() {
								if ("closed" !== this.readyState && this.transport.writable && !this.upgrading && this.writeBuffer.length) {
									var t2 = this.getWritablePackets();
									this.transport.send(t2), this.prevBufferLen = t2.length, this.emitReserved("flush");
								}
							}
						},
						{
							key: "getWritablePackets",
							value: function() {
								if (!(this.maxPayload && "polling" === this.transport.name && this.writeBuffer.length > 1)) return this.writeBuffer;
								for (var t2, e2 = 1, n3 = 0; n3 < this.writeBuffer.length; n3++) {
									var r2 = this.writeBuffer[n3].data;
									if (r2 && (e2 += "string" == typeof (t2 = r2) ? function(t3) {
										for (var e3 = 0, n4 = 0, r3 = 0, i2 = t3.length; r3 < i2; r3++) (e3 = t3.charCodeAt(r3)) < 128 ? n4 += 1 : e3 < 2048 ? n4 += 2 : e3 < 55296 || e3 >= 57344 ? n4 += 3 : (r3++, n4 += 4);
										return n4;
									}(t2) : Math.ceil(1.33 * (t2.byteLength || t2.size))), n3 > 0 && e2 > this.maxPayload) return this.writeBuffer.slice(0, n3);
									e2 += 2;
								}
								return this.writeBuffer;
							}
						},
						{
							key: "write",
							value: function(t2, e2, n3) {
								return this.sendPacket("message", t2, e2, n3), this;
							}
						},
						{
							key: "send",
							value: function(t2, e2, n3) {
								return this.sendPacket("message", t2, e2, n3), this;
							}
						},
						{
							key: "sendPacket",
							value: function(t2, e2, n3, r2) {
								if ("function" == typeof e2 && (r2 = e2, e2 = void 0), "function" == typeof n3 && (r2 = n3, n3 = null), "closing" !== this.readyState && "closed" !== this.readyState) {
									(n3 = n3 || {}).compress = false !== n3.compress;
									var i2 = {
										type: t2,
										data: e2,
										options: n3
									};
									this.emitReserved("packetCreate", i2), this.writeBuffer.push(i2), r2 && this.once("flush", r2), this.flush();
								}
							}
						},
						{
							key: "close",
							value: function() {
								var t2 = this, e2 = function() {
									t2.onClose("forced close"), t2.transport.close();
								}, n3 = function n4() {
									t2.off("upgrade", n4), t2.off("upgradeError", n4), e2();
								}, r2 = function() {
									t2.once("upgrade", n3), t2.once("upgradeError", n3);
								};
								return "opening" !== this.readyState && "open" !== this.readyState || (this.readyState = "closing", this.writeBuffer.length ? this.once("drain", function() {
									t2.upgrading ? r2() : e2();
								}) : this.upgrading ? r2() : e2()), this;
							}
						},
						{
							key: "onError",
							value: function(t2) {
								a2.priorWebsocketSuccess = false, this.emitReserved("error", t2), this.onClose("transport error", t2);
							}
						},
						{
							key: "onClose",
							value: function(t2, e2) {
								"opening" !== this.readyState && "open" !== this.readyState && "closing" !== this.readyState || (this.clearTimeoutFn(this.pingTimeoutTimer), this.transport.removeAllListeners("close"), this.transport.close(), this.transport.removeAllListeners(), "function" == typeof removeEventListener && (removeEventListener("beforeunload", this.beforeunloadEventListener, false), removeEventListener("offline", this.offlineEventListener, false)), this.readyState = "closed", this.id = null, this.emitReserved("close", t2, e2), this.writeBuffer = [], this.prevBufferLen = 0);
							}
						},
						{
							key: "filterUpgrades",
							value: function(t2) {
								for (var e2 = [], n3 = 0, r2 = t2.length; n3 < r2; n3++) ~this.transports.indexOf(t2[n3]) && e2.push(t2[n3]);
								return e2;
							}
						}
					]), a2;
				}(L);
				lt.protocol = 4, lt.protocol;
				var pt = "function" == typeof ArrayBuffer, dt = Object.prototype.toString, yt = "function" == typeof Blob || "undefined" != typeof Blob && "[object BlobConstructor]" === dt.call(Blob), vt = "function" == typeof File || "undefined" != typeof File && "[object FileConstructor]" === dt.call(File);
				function gt(t2) {
					return pt && (t2 instanceof ArrayBuffer || function(t3) {
						return "function" == typeof ArrayBuffer.isView ? ArrayBuffer.isView(t3) : t3.buffer instanceof ArrayBuffer;
					}(t2)) || yt && t2 instanceof Blob || vt && t2 instanceof File;
				}
				function mt(e2, n2) {
					if (!e2 || "object" !== t(e2)) return false;
					if (Array.isArray(e2)) {
						for (var r2 = 0, i2 = e2.length; r2 < i2; r2++) if (mt(e2[r2])) return true;
						return false;
					}
					if (gt(e2)) return true;
					if (e2.toJSON && "function" == typeof e2.toJSON && 1 === arguments.length) return mt(e2.toJSON(), true);
					for (var o2 in e2) if (Object.prototype.hasOwnProperty.call(e2, o2) && mt(e2[o2])) return true;
					return false;
				}
				function kt(t2) {
					var e2 = [], n2 = t2.data, r2 = t2;
					return r2.data = bt(n2, e2), r2.attachments = e2.length, {
						packet: r2,
						buffers: e2
					};
				}
				function bt(e2, n2) {
					if (!e2) return e2;
					if (gt(e2)) {
						var r2 = {
							_placeholder: true,
							num: n2.length
						};
						return n2.push(e2), r2;
					}
					if (Array.isArray(e2)) {
						for (var i2 = new Array(e2.length), o2 = 0; o2 < e2.length; o2++) i2[o2] = bt(e2[o2], n2);
						return i2;
					}
					if ("object" === t(e2) && !(e2 instanceof Date)) {
						var s2 = {};
						for (var a2 in e2) Object.prototype.hasOwnProperty.call(e2, a2) && (s2[a2] = bt(e2[a2], n2));
						return s2;
					}
					return e2;
				}
				function wt(t2, e2) {
					return t2.data = _t(t2.data, e2), delete t2.attachments, t2;
				}
				function _t(e2, n2) {
					if (!e2) return e2;
					if (e2 && true === e2._placeholder) {
						if ("number" == typeof e2.num && e2.num >= 0 && e2.num < n2.length) return n2[e2.num];
						throw new Error("illegal attachments");
					}
					if (Array.isArray(e2)) for (var r2 = 0; r2 < e2.length; r2++) e2[r2] = _t(e2[r2], n2);
					else if ("object" === t(e2)) for (var i2 in e2) Object.prototype.hasOwnProperty.call(e2, i2) && (e2[i2] = _t(e2[i2], n2));
					return e2;
				}
				var Et;
				(function(t2) {
					t2[t2.CONNECT = 0] = "CONNECT", t2[t2.DISCONNECT = 1] = "DISCONNECT", t2[t2.EVENT = 2] = "EVENT", t2[t2.ACK = 3] = "ACK", t2[t2.CONNECT_ERROR = 4] = "CONNECT_ERROR", t2[t2.BINARY_EVENT = 5] = "BINARY_EVENT", t2[t2.BINARY_ACK = 6] = "BINARY_ACK";
				})(Et || (Et = {}));
				var Ot = function() {
					function t2(n2) {
						e(this, t2), this.replacer = n2;
					}
					return r(t2, [
						{
							key: "encode",
							value: function(t3) {
								return t3.type !== Et.EVENT && t3.type !== Et.ACK || !mt(t3) ? [this.encodeAsString(t3)] : this.encodeAsBinary({
									type: t3.type === Et.EVENT ? Et.BINARY_EVENT : Et.BINARY_ACK,
									nsp: t3.nsp,
									data: t3.data,
									id: t3.id
								});
							}
						},
						{
							key: "encodeAsString",
							value: function(t3) {
								var e2 = "" + t3.type;
								return t3.type !== Et.BINARY_EVENT && t3.type !== Et.BINARY_ACK || (e2 += t3.attachments + "-"), t3.nsp && "/" !== t3.nsp && (e2 += t3.nsp + ","), null != t3.id && (e2 += t3.id), null != t3.data && (e2 += JSON.stringify(t3.data, this.replacer)), e2;
							}
						},
						{
							key: "encodeAsBinary",
							value: function(t3) {
								var e2 = kt(t3), n2 = this.encodeAsString(e2.packet), r2 = e2.buffers;
								return r2.unshift(n2), r2;
							}
						}
					]), t2;
				}(), At = function(n2) {
					o(a2, n2);
					var i2 = p(a2);
					function a2(t2) {
						var n3;
						return e(this, a2), (n3 = i2.call(this)).reviver = t2, n3;
					}
					return r(a2, [
						{
							key: "add",
							value: function(t2) {
								var e2;
								if ("string" == typeof t2) {
									if (this.reconstructor) throw new Error("got plaintext data when reconstructing a packet");
									var n3 = (e2 = this.decodeString(t2)).type === Et.BINARY_EVENT;
									n3 || e2.type === Et.BINARY_ACK ? (e2.type = n3 ? Et.EVENT : Et.ACK, this.reconstructor = new Rt(e2), 0 === e2.attachments && y(s(a2.prototype), "emitReserved", this).call(this, "decoded", e2)) : y(s(a2.prototype), "emitReserved", this).call(this, "decoded", e2);
								} else {
									if (!gt(t2) && !t2.base64) throw new Error("Unknown type: " + t2);
									if (!this.reconstructor) throw new Error("got binary data when not reconstructing a packet");
									(e2 = this.reconstructor.takeBinaryData(t2)) && (this.reconstructor = null, y(s(a2.prototype), "emitReserved", this).call(this, "decoded", e2));
								}
							}
						},
						{
							key: "decodeString",
							value: function(t2) {
								var e2 = 0, n3 = { type: Number(t2.charAt(0)) };
								if (void 0 === Et[n3.type]) throw new Error("unknown packet type " + n3.type);
								if (n3.type === Et.BINARY_EVENT || n3.type === Et.BINARY_ACK) {
									for (var r2 = e2 + 1; "-" !== t2.charAt(++e2) && e2 != t2.length;);
									var i3 = t2.substring(r2, e2);
									if (i3 != Number(i3) || "-" !== t2.charAt(e2)) throw new Error("Illegal attachments");
									n3.attachments = Number(i3);
								}
								if ("/" === t2.charAt(e2 + 1)) {
									for (var o2 = e2 + 1; ++e2;) {
										if ("," === t2.charAt(e2)) break;
										if (e2 === t2.length) break;
									}
									n3.nsp = t2.substring(o2, e2);
								} else n3.nsp = "/";
								var s2 = t2.charAt(e2 + 1);
								if ("" !== s2 && Number(s2) == s2) {
									for (var c2 = e2 + 1; ++e2;) {
										var u2 = t2.charAt(e2);
										if (null == u2 || Number(u2) != u2) {
											--e2;
											break;
										}
										if (e2 === t2.length) break;
									}
									n3.id = Number(t2.substring(c2, e2 + 1));
								}
								if (t2.charAt(++e2)) {
									var h2 = this.tryParse(t2.substr(e2));
									if (!a2.isPayloadValid(n3.type, h2)) throw new Error("invalid payload");
									n3.data = h2;
								}
								return n3;
							}
						},
						{
							key: "tryParse",
							value: function(t2) {
								try {
									return JSON.parse(t2, this.reviver);
								} catch (t3) {
									return false;
								}
							}
						},
						{
							key: "destroy",
							value: function() {
								this.reconstructor && (this.reconstructor.finishedReconstruction(), this.reconstructor = null);
							}
						}
					], [{
						key: "isPayloadValid",
						value: function(e2, n3) {
							switch (e2) {
								case Et.CONNECT: return "object" === t(n3);
								case Et.DISCONNECT: return void 0 === n3;
								case Et.CONNECT_ERROR: return "string" == typeof n3 || "object" === t(n3);
								case Et.EVENT:
								case Et.BINARY_EVENT: return Array.isArray(n3) && n3.length > 0;
								case Et.ACK:
								case Et.BINARY_ACK: return Array.isArray(n3);
							}
						}
					}]), a2;
				}(L), Rt = function() {
					function t2(n2) {
						e(this, t2), this.packet = n2, this.buffers = [], this.reconPack = n2;
					}
					return r(t2, [{
						key: "takeBinaryData",
						value: function(t3) {
							if (this.buffers.push(t3), this.buffers.length === this.reconPack.attachments) {
								var e2 = wt(this.reconPack, this.buffers);
								return this.finishedReconstruction(), e2;
							}
							return null;
						}
					}, {
						key: "finishedReconstruction",
						value: function() {
							this.reconPack = null, this.buffers = [];
						}
					}]), t2;
				}(), Tt = Object.freeze({
					__proto__: null,
					protocol: 5,
					get PacketType() {
						return Et;
					},
					Encoder: Ot,
					Decoder: At
				});
				function Ct(t2, e2, n2) {
					return t2.on(e2, n2), function() {
						t2.off(e2, n2);
					};
				}
				var Bt = Object.freeze({
					connect: 1,
					connect_error: 1,
					disconnect: 1,
					disconnecting: 1,
					newListener: 1,
					removeListener: 1
				}), St = function(t2) {
					o(a2, t2);
					var n2 = p(a2);
					function a2(t3, r2, o2) {
						var s2;
						return e(this, a2), (s2 = n2.call(this)).connected = false, s2.recovered = false, s2.receiveBuffer = [], s2.sendBuffer = [], s2._queue = [], s2.ids = 0, s2.acks = {}, s2.flags = {}, s2.io = t3, s2.nsp = r2, o2 && o2.auth && (s2.auth = o2.auth), s2._opts = i({}, o2), s2.io._autoConnect && s2.open(), s2;
					}
					return r(a2, [
						{
							key: "disconnected",
							get: function() {
								return !this.connected;
							}
						},
						{
							key: "subEvents",
							value: function() {
								if (!this.subs) {
									var t3 = this.io;
									this.subs = [
										Ct(t3, "open", this.onopen.bind(this)),
										Ct(t3, "packet", this.onpacket.bind(this)),
										Ct(t3, "error", this.onerror.bind(this)),
										Ct(t3, "close", this.onclose.bind(this))
									];
								}
							}
						},
						{
							key: "active",
							get: function() {
								return !!this.subs;
							}
						},
						{
							key: "connect",
							value: function() {
								return this.connected || (this.subEvents(), this.io._reconnecting || this.io.open(), "open" === this.io._readyState && this.onopen()), this;
							}
						},
						{
							key: "open",
							value: function() {
								return this.connect();
							}
						},
						{
							key: "send",
							value: function() {
								for (var t3 = arguments.length, e2 = new Array(t3), n3 = 0; n3 < t3; n3++) e2[n3] = arguments[n3];
								return e2.unshift("message"), this.emit.apply(this, e2), this;
							}
						},
						{
							key: "emit",
							value: function(t3) {
								if (Bt.hasOwnProperty(t3)) throw new Error("\"" + t3.toString() + "\" is a reserved event name");
								for (var e2 = arguments.length, n3 = new Array(e2 > 1 ? e2 - 1 : 0), r2 = 1; r2 < e2; r2++) n3[r2 - 1] = arguments[r2];
								if (n3.unshift(t3), this._opts.retries && !this.flags.fromQueue && !this.flags.volatile) return this._addToQueue(n3), this;
								var i2 = {
									type: Et.EVENT,
									data: n3,
									options: {}
								};
								if (i2.options.compress = false !== this.flags.compress, "function" == typeof n3[n3.length - 1]) {
									var o2 = this.ids++, s2 = n3.pop();
									this._registerAckCallback(o2, s2), i2.id = o2;
								}
								var a3 = this.io.engine && this.io.engine.transport && this.io.engine.transport.writable;
								return this.flags.volatile && (!a3 || !this.connected) || (this.connected ? (this.notifyOutgoingListeners(i2), this.packet(i2)) : this.sendBuffer.push(i2)), this.flags = {}, this;
							}
						},
						{
							key: "_registerAckCallback",
							value: function(t3, e2) {
								var n3, r2 = this, i2 = null !== (n3 = this.flags.timeout) && void 0 !== n3 ? n3 : this._opts.ackTimeout;
								if (void 0 !== i2) {
									var o2 = this.io.setTimeoutFn(function() {
										delete r2.acks[t3];
										for (var n4 = 0; n4 < r2.sendBuffer.length; n4++) r2.sendBuffer[n4].id === t3 && r2.sendBuffer.splice(n4, 1);
										e2.call(r2, /* @__PURE__ */ new Error("operation has timed out"));
									}, i2);
									this.acks[t3] = function() {
										r2.io.clearTimeoutFn(o2);
										for (var t4 = arguments.length, n4 = new Array(t4), i3 = 0; i3 < t4; i3++) n4[i3] = arguments[i3];
										e2.apply(r2, [null].concat(n4));
									};
								} else this.acks[t3] = e2;
							}
						},
						{
							key: "emitWithAck",
							value: function(t3) {
								for (var e2 = this, n3 = arguments.length, r2 = new Array(n3 > 1 ? n3 - 1 : 0), i2 = 1; i2 < n3; i2++) r2[i2 - 1] = arguments[i2];
								var o2 = void 0 !== this.flags.timeout || void 0 !== this._opts.ackTimeout;
								return new Promise(function(n4, i3) {
									r2.push(function(t4, e3) {
										return o2 ? t4 ? i3(t4) : n4(e3) : n4(t4);
									}), e2.emit.apply(e2, [t3].concat(r2));
								});
							}
						},
						{
							key: "_addToQueue",
							value: function(t3) {
								var e2, n3 = this;
								"function" == typeof t3[t3.length - 1] && (e2 = t3.pop());
								var r2 = {
									id: this.ids++,
									tryCount: 0,
									pending: false,
									args: t3,
									flags: i({ fromQueue: true }, this.flags)
								};
								t3.push(function(t4) {
									if (r2 === n3._queue[0]) {
										if (null !== t4) r2.tryCount > n3._opts.retries && (n3._queue.shift(), e2 && e2(t4));
										else if (n3._queue.shift(), e2) {
											for (var o2 = arguments.length, s2 = new Array(o2 > 1 ? o2 - 1 : 0), a3 = 1; a3 < o2; a3++) s2[a3 - 1] = arguments[a3];
											e2.apply(void 0, [null].concat(s2));
										}
										return r2.pending = false, n3._drainQueue();
									}
								}), this._queue.push(r2), this._drainQueue();
							}
						},
						{
							key: "_drainQueue",
							value: function() {
								if (0 !== this._queue.length) {
									var t3 = this._queue[0];
									if (!t3.pending) {
										t3.pending = true, t3.tryCount++;
										var e2 = this.ids;
										this.ids = t3.id, this.flags = t3.flags, this.emit.apply(this, t3.args), this.ids = e2;
									}
								}
							}
						},
						{
							key: "packet",
							value: function(t3) {
								t3.nsp = this.nsp, this.io._packet(t3);
							}
						},
						{
							key: "onopen",
							value: function() {
								var t3 = this;
								"function" == typeof this.auth ? this.auth(function(e2) {
									t3._sendConnectPacket(e2);
								}) : this._sendConnectPacket(this.auth);
							}
						},
						{
							key: "_sendConnectPacket",
							value: function(t3) {
								this.packet({
									type: Et.CONNECT,
									data: this._pid ? i({
										pid: this._pid,
										offset: this._lastOffset
									}, t3) : t3
								});
							}
						},
						{
							key: "onerror",
							value: function(t3) {
								this.connected || this.emitReserved("connect_error", t3);
							}
						},
						{
							key: "onclose",
							value: function(t3, e2) {
								this.connected = false, delete this.id, this.emitReserved("disconnect", t3, e2);
							}
						},
						{
							key: "onpacket",
							value: function(t3) {
								if (t3.nsp === this.nsp) switch (t3.type) {
									case Et.CONNECT:
										t3.data && t3.data.sid ? this.onconnect(t3.data.sid, t3.data.pid) : this.emitReserved("connect_error", /* @__PURE__ */ new Error("It seems you are trying to reach a Socket.IO server in v2.x with a v3.x client, but they are not compatible (more information here: https://socket.io/docs/v3/migrating-from-2-x-to-3-0/)"));
										break;
									case Et.EVENT:
									case Et.BINARY_EVENT:
										this.onevent(t3);
										break;
									case Et.ACK:
									case Et.BINARY_ACK:
										this.onack(t3);
										break;
									case Et.DISCONNECT:
										this.ondisconnect();
										break;
									case Et.CONNECT_ERROR:
										this.destroy();
										var e2 = new Error(t3.data.message);
										e2.data = t3.data.data, this.emitReserved("connect_error", e2);
								}
							}
						},
						{
							key: "onevent",
							value: function(t3) {
								var e2 = t3.data || [];
								null != t3.id && e2.push(this.ack(t3.id)), this.connected ? this.emitEvent(e2) : this.receiveBuffer.push(Object.freeze(e2));
							}
						},
						{
							key: "emitEvent",
							value: function(t3) {
								if (this._anyListeners && this._anyListeners.length) {
									var e2, n3 = g(this._anyListeners.slice());
									try {
										for (n3.s(); !(e2 = n3.n()).done;) e2.value.apply(this, t3);
									} catch (t4) {
										n3.e(t4);
									} finally {
										n3.f();
									}
								}
								y(s(a2.prototype), "emit", this).apply(this, t3), this._pid && t3.length && "string" == typeof t3[t3.length - 1] && (this._lastOffset = t3[t3.length - 1]);
							}
						},
						{
							key: "ack",
							value: function(t3) {
								var e2 = this, n3 = false;
								return function() {
									if (!n3) {
										n3 = true;
										for (var r2 = arguments.length, i2 = new Array(r2), o2 = 0; o2 < r2; o2++) i2[o2] = arguments[o2];
										e2.packet({
											type: Et.ACK,
											id: t3,
											data: i2
										});
									}
								};
							}
						},
						{
							key: "onack",
							value: function(t3) {
								var e2 = this.acks[t3.id];
								"function" == typeof e2 && (e2.apply(this, t3.data), delete this.acks[t3.id]);
							}
						},
						{
							key: "onconnect",
							value: function(t3, e2) {
								this.id = t3, this.recovered = e2 && this._pid === e2, this._pid = e2, this.connected = true, this.emitBuffered(), this.emitReserved("connect");
							}
						},
						{
							key: "emitBuffered",
							value: function() {
								var t3 = this;
								this.receiveBuffer.forEach(function(e2) {
									return t3.emitEvent(e2);
								}), this.receiveBuffer = [], this.sendBuffer.forEach(function(e2) {
									t3.notifyOutgoingListeners(e2), t3.packet(e2);
								}), this.sendBuffer = [];
							}
						},
						{
							key: "ondisconnect",
							value: function() {
								this.destroy(), this.onclose("io server disconnect");
							}
						},
						{
							key: "destroy",
							value: function() {
								this.subs && (this.subs.forEach(function(t3) {
									return t3();
								}), this.subs = void 0), this.io._destroy(this);
							}
						},
						{
							key: "disconnect",
							value: function() {
								return this.connected && this.packet({ type: Et.DISCONNECT }), this.destroy(), this.connected && this.onclose("io client disconnect"), this;
							}
						},
						{
							key: "close",
							value: function() {
								return this.disconnect();
							}
						},
						{
							key: "compress",
							value: function(t3) {
								return this.flags.compress = t3, this;
							}
						},
						{
							key: "volatile",
							get: function() {
								return this.flags.volatile = true, this;
							}
						},
						{
							key: "timeout",
							value: function(t3) {
								return this.flags.timeout = t3, this;
							}
						},
						{
							key: "onAny",
							value: function(t3) {
								return this._anyListeners = this._anyListeners || [], this._anyListeners.push(t3), this;
							}
						},
						{
							key: "prependAny",
							value: function(t3) {
								return this._anyListeners = this._anyListeners || [], this._anyListeners.unshift(t3), this;
							}
						},
						{
							key: "offAny",
							value: function(t3) {
								if (!this._anyListeners) return this;
								if (t3) {
									for (var e2 = this._anyListeners, n3 = 0; n3 < e2.length; n3++) if (t3 === e2[n3]) return e2.splice(n3, 1), this;
								} else this._anyListeners = [];
								return this;
							}
						},
						{
							key: "listenersAny",
							value: function() {
								return this._anyListeners || [];
							}
						},
						{
							key: "onAnyOutgoing",
							value: function(t3) {
								return this._anyOutgoingListeners = this._anyOutgoingListeners || [], this._anyOutgoingListeners.push(t3), this;
							}
						},
						{
							key: "prependAnyOutgoing",
							value: function(t3) {
								return this._anyOutgoingListeners = this._anyOutgoingListeners || [], this._anyOutgoingListeners.unshift(t3), this;
							}
						},
						{
							key: "offAnyOutgoing",
							value: function(t3) {
								if (!this._anyOutgoingListeners) return this;
								if (t3) {
									for (var e2 = this._anyOutgoingListeners, n3 = 0; n3 < e2.length; n3++) if (t3 === e2[n3]) return e2.splice(n3, 1), this;
								} else this._anyOutgoingListeners = [];
								return this;
							}
						},
						{
							key: "listenersAnyOutgoing",
							value: function() {
								return this._anyOutgoingListeners || [];
							}
						},
						{
							key: "notifyOutgoingListeners",
							value: function(t3) {
								if (this._anyOutgoingListeners && this._anyOutgoingListeners.length) {
									var e2, n3 = g(this._anyOutgoingListeners.slice());
									try {
										for (n3.s(); !(e2 = n3.n()).done;) e2.value.apply(this, t3.data);
									} catch (t4) {
										n3.e(t4);
									} finally {
										n3.f();
									}
								}
							}
						}
					]), a2;
				}(L);
				function Nt(t2) {
					t2 = t2 || {}, this.ms = t2.min || 100, this.max = t2.max || 1e4, this.factor = t2.factor || 2, this.jitter = t2.jitter > 0 && t2.jitter <= 1 ? t2.jitter : 0, this.attempts = 0;
				}
				Nt.prototype.duration = function() {
					var t2 = this.ms * Math.pow(this.factor, this.attempts++);
					if (this.jitter) {
						var e2 = Math.random(), n2 = Math.floor(e2 * this.jitter * t2);
						t2 = 0 == (1 & Math.floor(10 * e2)) ? t2 - n2 : t2 + n2;
					}
					return 0 | Math.min(t2, this.max);
				}, Nt.prototype.reset = function() {
					this.attempts = 0;
				}, Nt.prototype.setMin = function(t2) {
					this.ms = t2;
				}, Nt.prototype.setMax = function(t2) {
					this.max = t2;
				}, Nt.prototype.setJitter = function(t2) {
					this.jitter = t2;
				};
				var xt = function(n2) {
					o(s2, n2);
					var i2 = p(s2);
					function s2(n3, r2) {
						var o2, a2;
						e(this, s2), (o2 = i2.call(this)).nsps = {}, o2.subs = [], n3 && "object" === t(n3) && (r2 = n3, n3 = void 0), (r2 = r2 || {}).path = r2.path || "/socket.io", o2.opts = r2, D(f(o2), r2), o2.reconnection(false !== r2.reconnection), o2.reconnectionAttempts(r2.reconnectionAttempts || Infinity), o2.reconnectionDelay(r2.reconnectionDelay || 1e3), o2.reconnectionDelayMax(r2.reconnectionDelayMax || 5e3), o2.randomizationFactor(null !== (a2 = r2.randomizationFactor) && void 0 !== a2 ? a2 : .5), o2.backoff = new Nt({
							min: o2.reconnectionDelay(),
							max: o2.reconnectionDelayMax(),
							jitter: o2.randomizationFactor()
						}), o2.timeout(null == r2.timeout ? 2e4 : r2.timeout), o2._readyState = "closed", o2.uri = n3;
						var c2 = r2.parser || Tt;
						return o2.encoder = new c2.Encoder(), o2.decoder = new c2.Decoder(), o2._autoConnect = false !== r2.autoConnect, o2._autoConnect && o2.open(), o2;
					}
					return r(s2, [
						{
							key: "reconnection",
							value: function(t2) {
								return arguments.length ? (this._reconnection = !!t2, this) : this._reconnection;
							}
						},
						{
							key: "reconnectionAttempts",
							value: function(t2) {
								return void 0 === t2 ? this._reconnectionAttempts : (this._reconnectionAttempts = t2, this);
							}
						},
						{
							key: "reconnectionDelay",
							value: function(t2) {
								var e2;
								return void 0 === t2 ? this._reconnectionDelay : (this._reconnectionDelay = t2, null === (e2 = this.backoff) || void 0 === e2 || e2.setMin(t2), this);
							}
						},
						{
							key: "randomizationFactor",
							value: function(t2) {
								var e2;
								return void 0 === t2 ? this._randomizationFactor : (this._randomizationFactor = t2, null === (e2 = this.backoff) || void 0 === e2 || e2.setJitter(t2), this);
							}
						},
						{
							key: "reconnectionDelayMax",
							value: function(t2) {
								var e2;
								return void 0 === t2 ? this._reconnectionDelayMax : (this._reconnectionDelayMax = t2, null === (e2 = this.backoff) || void 0 === e2 || e2.setMax(t2), this);
							}
						},
						{
							key: "timeout",
							value: function(t2) {
								return arguments.length ? (this._timeout = t2, this) : this._timeout;
							}
						},
						{
							key: "maybeReconnectOnOpen",
							value: function() {
								!this._reconnecting && this._reconnection && 0 === this.backoff.attempts && this.reconnect();
							}
						},
						{
							key: "open",
							value: function(t2) {
								var e2 = this;
								if (~this._readyState.indexOf("open")) return this;
								this.engine = new lt(this.uri, this.opts);
								var n3 = this.engine, r2 = this;
								this._readyState = "opening", this.skipReconnect = false;
								var i3 = Ct(n3, "open", function() {
									r2.onopen(), t2 && t2();
								}), o2 = Ct(n3, "error", function(n4) {
									r2.cleanup(), r2._readyState = "closed", e2.emitReserved("error", n4), t2 ? t2(n4) : r2.maybeReconnectOnOpen();
								});
								if (false !== this._timeout) {
									var s3 = this._timeout;
									0 === s3 && i3();
									var a2 = this.setTimeoutFn(function() {
										i3(), n3.close(), n3.emit("error", /* @__PURE__ */ new Error("timeout"));
									}, s3);
									this.opts.autoUnref && a2.unref(), this.subs.push(function() {
										clearTimeout(a2);
									});
								}
								return this.subs.push(i3), this.subs.push(o2), this;
							}
						},
						{
							key: "connect",
							value: function(t2) {
								return this.open(t2);
							}
						},
						{
							key: "onopen",
							value: function() {
								this.cleanup(), this._readyState = "open", this.emitReserved("open");
								var t2 = this.engine;
								this.subs.push(Ct(t2, "ping", this.onping.bind(this)), Ct(t2, "data", this.ondata.bind(this)), Ct(t2, "error", this.onerror.bind(this)), Ct(t2, "close", this.onclose.bind(this)), Ct(this.decoder, "decoded", this.ondecoded.bind(this)));
							}
						},
						{
							key: "onping",
							value: function() {
								this.emitReserved("ping");
							}
						},
						{
							key: "ondata",
							value: function(t2) {
								try {
									this.decoder.add(t2);
								} catch (t3) {
									this.onclose("parse error", t3);
								}
							}
						},
						{
							key: "ondecoded",
							value: function(t2) {
								var e2 = this;
								it(function() {
									e2.emitReserved("packet", t2);
								}, this.setTimeoutFn);
							}
						},
						{
							key: "onerror",
							value: function(t2) {
								this.emitReserved("error", t2);
							}
						},
						{
							key: "socket",
							value: function(t2, e2) {
								var n3 = this.nsps[t2];
								return n3 || (n3 = new St(this, t2, e2), this.nsps[t2] = n3), this._autoConnect && n3.connect(), n3;
							}
						},
						{
							key: "_destroy",
							value: function(t2) {
								for (var e2 = 0, n3 = Object.keys(this.nsps); e2 < n3.length; e2++) {
									var r2 = n3[e2];
									if (this.nsps[r2].active) return;
								}
								this._close();
							}
						},
						{
							key: "_packet",
							value: function(t2) {
								for (var e2 = this.encoder.encode(t2), n3 = 0; n3 < e2.length; n3++) this.engine.write(e2[n3], t2.options);
							}
						},
						{
							key: "cleanup",
							value: function() {
								this.subs.forEach(function(t2) {
									return t2();
								}), this.subs.length = 0, this.decoder.destroy();
							}
						},
						{
							key: "_close",
							value: function() {
								this.skipReconnect = true, this._reconnecting = false, this.onclose("forced close"), this.engine && this.engine.close();
							}
						},
						{
							key: "disconnect",
							value: function() {
								return this._close();
							}
						},
						{
							key: "onclose",
							value: function(t2, e2) {
								this.cleanup(), this.backoff.reset(), this._readyState = "closed", this.emitReserved("close", t2, e2), this._reconnection && !this.skipReconnect && this.reconnect();
							}
						},
						{
							key: "reconnect",
							value: function() {
								var t2 = this;
								if (this._reconnecting || this.skipReconnect) return this;
								var e2 = this;
								if (this.backoff.attempts >= this._reconnectionAttempts) this.backoff.reset(), this.emitReserved("reconnect_failed"), this._reconnecting = false;
								else {
									var n3 = this.backoff.duration();
									this._reconnecting = true;
									var r2 = this.setTimeoutFn(function() {
										e2.skipReconnect || (t2.emitReserved("reconnect_attempt", e2.backoff.attempts), e2.skipReconnect || e2.open(function(n4) {
											n4 ? (e2._reconnecting = false, e2.reconnect(), t2.emitReserved("reconnect_error", n4)) : e2.onreconnect();
										}));
									}, n3);
									this.opts.autoUnref && r2.unref(), this.subs.push(function() {
										clearTimeout(r2);
									});
								}
							}
						},
						{
							key: "onreconnect",
							value: function() {
								var t2 = this.backoff.attempts;
								this._reconnecting = false, this.backoff.reset(), this.emitReserved("reconnect", t2);
							}
						}
					]), s2;
				}(L), Lt = {};
				function Pt(e2, n2) {
					"object" === t(e2) && (n2 = e2, e2 = void 0);
					var r2, i2 = function(t2) {
						var e3 = arguments.length > 1 && void 0 !== arguments[1] ? arguments[1] : "", n3 = arguments.length > 2 ? arguments[2] : void 0, r3 = t2;
						n3 = n3 || "undefined" != typeof location && location, t2 ??= n3.protocol + "//" + n3.host, "string" == typeof t2 && ("/" === t2.charAt(0) && (t2 = "/" === t2.charAt(1) ? n3.protocol + t2 : n3.host + t2), /^(https?|wss?):\/\//.test(t2) || (t2 = void 0 !== n3 ? n3.protocol + "//" + t2 : "https://" + t2), r3 = ft(t2)), r3.port || (/^(http|ws)$/.test(r3.protocol) ? r3.port = "80" : /^(http|ws)s$/.test(r3.protocol) && (r3.port = "443")), r3.path = r3.path || "/";
						var i3 = -1 !== r3.host.indexOf(":") ? "[" + r3.host + "]" : r3.host;
						return r3.id = r3.protocol + "://" + i3 + ":" + r3.port + e3, r3.href = r3.protocol + "://" + i3 + (n3 && n3.port === r3.port ? "" : ":" + r3.port), r3;
					}(e2, (n2 = n2 || {}).path || "/socket.io"), o2 = i2.source, s2 = i2.id, a2 = i2.path, c2 = Lt[s2] && a2 in Lt[s2].nsps;
					return n2.forceNew || n2["force new connection"] || false === n2.multiplex || c2 ? r2 = new xt(o2, n2) : (Lt[s2] || (Lt[s2] = new xt(o2, n2)), r2 = Lt[s2]), i2.query && !n2.query && (n2.query = i2.queryKey), r2.socket(i2.path, n2);
				}
				return i(Pt, {
					Manager: xt,
					Socket: St,
					io: Pt,
					connect: Pt
				}), Pt;
			});
		} })());
		window.uc = window.uc || {};
		if (!window.uc.ams) (function() {
			const logPrefix = "# AMS: ";
			this.socket = null;
			this.pluginData = null;
			this.options = null;
			this.debug = null;
			this.initConnection = (options) => {
				if (!this.debug) this.debug = window.uc.log.create(logPrefix);
				this.debug.info("initConnection options: ", options);
				this.options = options;
				if (!this.options.url) {
					this.debug.error("Missing URL");
					return;
				}
				this.debug.info("Getting Secure API Key");
				apex.server.plugin(this.options.ajaxIdentifier, { x01: "GET-TEMP" }, {
					success: (data) => {
						this.debug.info("initConnection success: ", data);
						if (data.temp_key) {
							this.options.apiKey = data.temp_key;
							this.debug.info("Connecting to UC Cloud socket server: ", this.options.url, this.options.apiKey, this.options.rooms);
							this.socket = io(this.options.url, {
								auth: {
									api_key: this.options.apiKey?.trim(),
									rooms: this.options.rooms?.split(",").map((room) => room?.trim()).join(","),
									username: this.options.username?.trim(),
									session_id: this.options.sessionId?.trim()
								},
								transports: ["websocket", "polling"]
							});
						} else {
							this.debug.info("Connecting to on premise socket server: ", this.options.url, this.options.rooms);
							this.socket = io(this.options.url, {
								auth: { rooms: this.options.rooms?.split(",").map((room) => room?.trim()).join(",") },
								transports: ["websocket", "polling"]
							});
						}
						this.socket.on("connect", (...args) => {
							this.debug.info("connect", ...args);
						});
						this.socket.on("connect_error", async (err) => {
							if (err.message === "Temporary key is not in the rooms, ignoring connection") {
								const result = await apex.server.plugin(this.options.ajaxIdentifier, { x01: "GET-TEMP" });
								if (result.temp_key) {
									this.options.apiKey = result.temp_key;
									this.debug.info("Connecting to UC Cloud socket server: ", this.options.url, this.options.apiKey, this.options.rooms);
									this.socket = io(this.options.url, {
										auth: {
											api_key: this.options.apiKey?.trim(),
											rooms: this.options.rooms?.split(",").map((room) => room?.trim()).join(","),
											username: this.options.username?.trim(),
											session_id: this.options.sessionId?.trim()
										},
										transports: ["websocket", "polling"]
									});
								}
							} else apex.message.showErrors([{
								type: "error",
								location: "page",
								message: err.message,
								unsafe: false
							}]);
						});
						this.socket.on("disconnect", (...args) => {
							this.debug.warn("disconnected", ...args);
							this.debug.error("Server disconnected.");
							this.debug.warn("Make sure you have a valid API key and the server is running.");
						});
						this.socket.on("disconnecting", (...args) => {
							this.debug.info("disconnecting", ...args);
						});
						this.socket.on("newListener", (...args) => {
							this.debug.info("newListener", ...args);
						});
						this.socket.on("removeListener", (...args) => {
							this.debug.info("removeListener", ...args);
						});
						this.socket.on(this.options.clientListenEventName, (data2) => {
							if (data2.type === "UC-AMS-RATE-LIMIT") {
								this.debug.warn("Rate limit exceeded. Please try again later.");
								apex.message.showErrors([{
									type: "error",
									location: "page",
									message: "Rate limit exceeded. Please try again later.",
									unsafe: false
								}]);
								return;
							}
							if (data2.type === "UC-AMS-ERROR") {
								this.debug.error("ERROR: Room has changed, you have been disconnected...");
								apex.message.showErrors([{
									type: "error",
									location: "page",
									message: "Room has changed, you have been disconnected...",
									unsafe: false
								}]);
								return;
							}
							this.debug.info("Received data: ", data2);
							if (typeof data2.amsdata === "string") try {
								data2.amsdata = JSON.parse(data2.amsdata);
							} catch (e) {
								this.debug.error("Error parsing JSON: ", e);
							}
							if (this.options.customEventHandler) this.options.customEventHandler(data2);
							else apex.event.trigger(document, "uc-ams-event", data2);
						});
					},
					error: function(jqXHR, textStatus, errorThrown) {
						apex.debug.error("Error in Plugin: ", jqXHR, textStatus, errorThrown);
						apex.message.clearErrors();
						apex.message.showErrors([{
							type: "error",
							location: "page",
							message: errorThrown,
							unsafe: false
						}]);
					}
				});
			};
			this.emit = (incomingData) => {
				if (!incomingData) return;
				this.pluginData = {
					...this.pluginData,
					...incomingData
				};
				this.debug.info("emit data: ", this.pluginData);
				if (this.pluginData.rooms && !Array.isArray(this.pluginData.rooms)) this.pluginData.rooms = this.pluginData.rooms.split(",").map((room) => room?.trim()).join(",");
				this.socket.emit(this.options.clientSendEventName, this.pluginData);
			};
			this.broadcast = (incomingData) => {
				if (!incomingData) return;
				this.pluginData = {
					...this.pluginData,
					...incomingData,
					broadcast: true
				};
				this.debug.info("broadcast data: ", this.pluginData);
				if (this.pluginData.rooms && !Array.isArray(this.pluginData.rooms)) this.pluginData.rooms = this.pluginData.rooms.split(",").map((room) => room?.trim()).join(",");
				this.socket.emit(this.options.clientSendEventName, this.pluginData);
			};
			this.send = (incomingData) => {
				if (!incomingData) return;
				this.debug.info(`send data: ${JSON.stringify(this.pluginData)} incomingData: ${JSON.stringify(incomingData)}`);
				this.pluginData = {
					...this.pluginData,
					...incomingData
				};
				this.debug.info(`merged pluginData and incomingData: ${JSON.stringify(this.pluginData)}`);
				this.debug.info(`dataType: ${this.pluginData.dataType}`);
				try {
					if (this.pluginData.dataType === "JSON") this.pluginData.amsdata = JSON.parse(this.pluginData.amsdata);
				} catch (e) {
					this.debug.error("Error parsing JSON: ", e);
					apex.message.clearErrors();
					apex.message.showErrors([{
						type: "error",
						location: "page",
						message: `Error parsing JSON: ${e}`,
						unsafe: false
					}]);
					throw e;
				}
				if (this.pluginData.dataType === "JSON") {
					this.debug.info("send success: ", this.pluginData);
					this.socket.emit(this.options.clientSendEventName, {
						amsdata: this.pluginData.amsdata,
						rooms: this.pluginData.rooms,
						broadcast: this.pluginData.broadcast
					});
				} else {
					this.debug.info("sending plugin request");
					apex.server.plugin(this.pluginData.ajaxIdentifier, {}, { success: (data) => {
						this.debug.info("send success: ", {
							amsdata: data.amsdata,
							rooms: data.rooms,
							broadcast: data.broadcast
						});
						this.socket.emit(this.options.clientSendEventName, {
							amsdata: data.amsdata,
							rooms: data.rooms,
							broadcast: data.broadcast
						});
					} });
				}
			};
			this.joinRooms = (rooms) => {
				if (!rooms) return;
				if (!this.socket) {
					this.debug?.error("joinRooms called before socket is connected");
					return;
				}
				const roomStr = Array.isArray(rooms) ? rooms.join(",") : rooms;
				this.debug?.info("joinRooms: ", roomStr);
				this.socket.emit("join-rooms", { rooms: roomStr });
				if (this.options.rooms) this.options.rooms = `${this.options.rooms},${roomStr}`;
				else this.options.rooms = roomStr;
			};
			window.uc.ams = this;
		}).bind({})();
		window.uc = window.uc || {};
		window.uc.log = window.uc.log || { create: function(pPrefix) {
			apex.debug.info("... uc.log: create a new instance with prefix \"" + pPrefix + "\"");
			return {
				trace: (...args) => {
					apex.debug.trace(pPrefix, ...args);
				},
				error: (...args) => {
					apex.debug.error(pPrefix, ...args);
				},
				info: (...args) => {
					apex.debug.info(pPrefix, ...args);
				},
				warn: (...args) => {
					apex.debug.warn(pPrefix, ...args);
				}
			};
		} };
		window.io = import_socket_io_min.default;
	})();
	/*!
	* Socket.IO v4.6.0
	* (c) 2014-2023 Guillermo Rauch
	* Released under the MIT License.
	*/
	//#endregion
	//#region src/APEXchat.svelte
	var root_1 = /* @__PURE__ */ from_html(`<p>Initializing...</p>`);
	var root_2 = /* @__PURE__ */ from_html(`<button aria-label="Open chat" type="button" class="t-Button t-Button--icon t-Button--header"><span aria-hidden="true" class="t-Icon fa fa-comments-o"></span></button> <dialog class="uc-chat-dialog svelte-zcpgih"><!></dialog>`, 1);
	var root = /* @__PURE__ */ from_html(`<div class="uc-chat svelte-zcpgih"><!></div>`);
	var $$css = {
		hash: "svelte-zcpgih",
		code: "\n  /* The only plain text input in the component is the group-name field. The 4em\n     of right padding was copy-pasted from the composer's textarea, where it had\n     once made room for an absolutely positioned send button — here it just kept\n     the caret out of a third of the field. */.uc-chat input.apex-item-text {width:100%;padding:0.5em 0.6em;min-height:2.25em;}body {--uc-chat-component-background-color: var(\n      --ut-component-background-color,\n      #fff\n    );--uc-chat-component-border-radius: var(\n      --ut-component-border-radius,\n      0.125em\n    );--uc-chat-component-border-color: var(\n      --ut-component-border-color,\n      rgba(0, 0, 0, 0.1)\n    );--uc-chat-shadow-md: var(\n      --ut-shadow-md,\n      0 0.75em 1.5em -0.75em rgba(0, 0, 0, 0.3)\n    );--uc-chat-shadow-sm: var(\n      --ut-shadow-sm,\n      0 0.125em 0.25em -0.125em rgba(0, 0, 0, 0.1)\n    );--uc-chat-component-text-title-color: var(\n      --ut-component-text-title-color,\n      #000\n    );--uc-chat-component-text-muted-color: var(\n      --ut-component-text-muted-color,\n      rgba(0, 0, 0, 0.65)\n    );--uc-chat-component-highlight-background-color: var(\n      --ut-component-highlight-background-color,\n      rgba(0, 0, 0, 0.025)\n    );--uc-chat-footer-background-color: var(\n      --ut-footer-background-color,\n      #f2f2f2\n    );\n    /* Divisions *inside* a card, which the theme keeps lighter than the card's\n       own outline. Used so a tool card's internal rules do not read as loudly\n       as its edge. */--uc-chat-component-inner-border-color: var(\n      --ut-component-inner-border-color,\n      rgba(0, 0, 0, 0.05)\n    );\n\n    /* colors */--uc-chat-danger-color: var(--ut-palette-danger, #cb1100);\n\n    /* === Semantic surfaces ================================================\n       One token per role. Before this existed, --uc-chat-footer-background-color\n       was doing three unrelated jobs at once (transcript backdrop, inset code\n       fill, hover feedback), which is why a card's header could end up exactly\n       the same grey as the canvas behind the card. */\n\n    /* Raised chrome and message cards: the surface an APEX region is painted on. */--uc-chat-surface-background-color: var(\n      --ut-component-background-color,\n      #fff\n    );\n    /* The transcript backdrop — one step recessed from the surface. APEX's own\n       highlight tint is translucent and already flips direction per theme\n       (black in light themes, white in dark ones), so the recess follows the\n       host theme instead of guessing. */--uc-chat-canvas-background-color: var(\n      --ut-component-highlight-background-color,\n      rgba(0, 0, 0, 0.025)\n    );\n    /* Payloads inset INTO a card (code blocks, tool JSON, reasoning). Derived\n       from the theme's title text colour so it darkens light themes and lightens\n       dark ones without a second variable. The plain var() above it is the\n       fallback for engines without color-mix(). */--uc-chat-inset-background-color: var(\n      --ut-component-highlight-background-color,\n      rgba(0, 0, 0, 0.025)\n    );--uc-chat-inset-background-color: color-mix(\n      in srgb,\n      var(--ut-component-text-title-color, #000) 5%,\n      transparent\n    );\n    /* Hover feedback on quiet controls. */--uc-chat-hover-background-color: var(\n      --ut-component-highlight-background-color,\n      rgba(0, 0, 0, 0.025)\n    );\n\n    /* === Accent ===========================================================\n       The app's own primary, not a fixed palette swatch: --u-color-31 is the\n       same blue in every Vita variant, so a red or Redwood app used to get a\n       blue chat. --ut-palette-primary + its contrast are guaranteed to be a\n       legible pair by the theme itself. */--uc-chat-accent-color: var(\n      --ut-palette-primary,\n      var(--u-color-31, #1a8bc9)\n    );--uc-chat-accent-contrast-color: var(--ut-palette-primary-contrast, #fff);\n\n    /* Status colours from the theme palette, so success/warning/danger read the\n       same here as in every other region — and survive dark mode, which the\n       hardcoded pastels they replace did not. */--uc-chat-success-color: var(--ut-palette-success, #278701);--uc-chat-warning-color: var(--ut-palette-warning, #ffc628);\n\n    /* === Radius scale =====================================================\n       Three steps plus a pill. Message bubbles are not APEX components, so they\n       deliberately do NOT inherit --ut-component-border-radius (0.125rem in\n       Vita — square enough to look broken on a bubble); everything that is\n       chrome still uses the theme radius. */--uc-chat-radius-sm: 0.25em;--uc-chat-radius-md: 0.5em;--uc-chat-radius-lg: 0.75em;--uc-chat-radius-pill: 999em;\n\n    /* === Spacing scale ==================================================== */--uc-chat-space-1: 0.25em;--uc-chat-space-2: 0.5em;--uc-chat-space-3: 0.75em;--uc-chat-space-4: 1em;\n\n    /* Width of the assistant gutter: avatar + the gap after it. Every element in\n       the assistant column (bubble, reasoning, tool card, meta row) is aligned\n       to this one number, so they finally share a left edge. */--uc-chat-ai-avatar-size: 2em;--uc-chat-ai-gutter: 2.75em;\n\n    /* === Bars =============================================================\n       One measure for every header and every composer bar in every mode. They\n       used to be hand-set in px and no two agreed: the AI header was 48px, its\n       footer 50px, the user-chat header 48px, its footer 50px, the channel\n       header 48px and the thread header 42px — so a thread panel opening beside\n       a channel put two \"top bars\" at different heights next to each other.\n       Fixed heights also clipped the composer, whose textarea may grow to 10em;\n       every consumer applies this as a min-height instead. */--uc-chat-bar-height: 3em;--uc-chat-ai-bar-height: var(--uc-chat-bar-height);\n\n    /* === Avatars ==========================================================\n       Avatar.svelte sizes BOTH the tile and the initials inside it from this\n       one number, so a mount point sets the size once and nothing else has to\n       know. Before this, the tile was declared in four places (chat list 3.2em,\n       user list 3.2em, message rows 2em, thread 1.8em) and the initials were\n       then re-scaled by three separate :global() overrides reaching into\n       Avatar from the outside. It must be set on an element that is itself at\n       1em, or the em resolves against a scaled font-size — which is exactly how\n       the old sizes drifted. */--uc-chat-avatar-size: 2em;--uc-chat-font-base: system-ui, -apple-system, BlinkMacSystemFont,\n      \"Segoe UI\", Roboto, Oxygen, Ubuntu, Cantarell, \"Fira Sans\", \"Droid Sans\",\n      \"Helvetica Neue\", sans-serif;--uc-chat-font-mono: ui-monospace, SFMono-Regular, \"SF Mono\", Menlo,\n      Consolas, monospace;}.uc-chat.svelte-zcpgih {font-size:1em;font-family:var(--uc-chat-font-base);max-height:100%;overflow:auto;}.uc-chat-dialog.svelte-zcpgih {padding:0;border:1px solid var(--uc-chat-component-border-color);margin-top:5em;width:90vw;max-width:60em;height:80vh;max-height:1300px;background:var(--uc-chat-component-background-color);border-radius:var(--uc-chat-component-border-radius);box-shadow:var(--uc-chat-shadow-md), var(--uc-chat-shadow-sm);outline:none;\n    /* The pane inside paints its own surface right up to the corner; without\n       this its square corners show through the dialog's rounded ones in any\n       theme whose radius is more than a couple of pixels (Redwood: 6px). */overflow:hidden;}body:has(.uc-chat-dialog[open]) {overflow:hidden;}.uc-chat-dialog.svelte-zcpgih::backdrop {background-color:var(--jui-overlay-background-color, rgba(0, 0, 0, 0.25));}.uc-chat-dialog.svelte-zcpgih,\n  .uc-chat-dialog.svelte-zcpgih::backdrop {transition:display 0.2s allow-discrete,\n      overlay 0.2s allow-discrete,\n      opacity 0.2s;opacity:0;}\n\n  @media (prefers-reduced-motion) {.uc-chat-dialog.svelte-zcpgih,\n    .uc-chat-dialog.svelte-zcpgih::backdrop {transition:none;}\n  }.uc-chat-dialog[open].svelte-zcpgih {opacity:1;&::backdrop {opacity:1;}}\n\n  @starting-style {.uc-chat-dialog[open].svelte-zcpgih,\n    .uc-chat-dialog[open].svelte-zcpgih::backdrop {opacity:0;}\n  }"
	};
	function APEXchat($$anchor, $$props) {
		push($$props, true);
		append_styles$1($$anchor, $$css);
		/**
		* @typedef {Object} Props
		* @property {string} [regionId]
		* @property {string} [ajaxId]
		* @property {boolean} [useAms]
		* @property {string} [amsUrl]
		* @property {string} [userId]
		* @property {'dialog' | 'region'} [displayMode]
		* @property {'user' | 'ai' | 'channel'} [chatMode]
		* @property {boolean} [singleChatMode]
		* @property {string} [roomId]
		* @property {string} [maxHeight]
		* @property {string} [agentCode]
		* @property {number} [agentVersion]
		* @property {string} [sessionId]
		* @property {boolean} [showReasoning]
		* @property {boolean} [showTools]
		* @property {boolean} [showMetadata]
		* @property {boolean} [showDebug]
		* @property {string} [suggestedPrompts]
		* @property {string} [headerTitle]
		* @property {string} [avatarIcon]
		* @property {string} [welcomeMessage]
		* @property {string} [minHeight]
		* @property {'dots' | 'braille' | 'plasma' | 'matrix'} [thinkingAnimation]
		* @property {'off' | 'status' | 'tools'} [thinkingDetail]
		* @property {boolean} [autoTitle]
		* @property {boolean} [collectFeedback]
		*/
		/** @type {Props} */
		let regionId = prop($$props, "regionId", 7, ""), ajaxId = prop($$props, "ajaxId", 7, ""), useAms = prop($$props, "useAms", 7, false), amsUrl = prop($$props, "amsUrl", 7, ""), userId = prop($$props, "userId", 7, ""), displayMode = prop($$props, "displayMode", 7, "dialog"), chatMode = prop($$props, "chatMode", 7, "user"), singleChatMode = prop($$props, "singleChatMode", 7, false), roomId = prop($$props, "roomId", 7, ""), maxHeight = prop($$props, "maxHeight", 7, ""), agentCode = prop($$props, "agentCode", 7, ""), agentVersion = prop($$props, "agentVersion", 7, null), sessionId = prop($$props, "sessionId", 7, ""), showReasoning = prop($$props, "showReasoning", 7, false), showTools = prop($$props, "showTools", 7, false), showMetadata = prop($$props, "showMetadata", 7, false), showDebug = prop($$props, "showDebug", 7, false), suggestedPrompts = prop($$props, "suggestedPrompts", 7, ""), headerTitle = prop($$props, "headerTitle", 7, ""), avatarIcon = prop($$props, "avatarIcon", 7, ""), welcomeMessage = prop($$props, "welcomeMessage", 7, ""), minHeight = prop($$props, "minHeight", 7, ""), thinkingAnimation = prop($$props, "thinkingAnimation", 7, ""), thinkingDetail = prop($$props, "thinkingDetail", 7, ""), autoTitle = prop($$props, "autoTitle", 7, false), collectFeedback = prop($$props, "collectFeedback", 7, false);
		let initialized = /* @__PURE__ */ state(false);
		onMount(() => {
			initInstance(regionId(), ajaxId());
			if (maxHeight() && get(chatEl) && displayMode() !== "dialog") {
				get(chatEl).style.height = /^\d+$/.test(maxHeight()) ? `${maxHeight()}px` : maxHeight();
				get(chatEl).style.overflow = "hidden";
			}
			setTimeout(() => {
				if (useAms()) initAms(amsUrl(), ajaxId(), userId());
			}, 1e3);
			set(initialized, true);
		});
		let chatEl = /* @__PURE__ */ state(void 0);
		let dialog = /* @__PURE__ */ state(void 0);
		let opened = /* @__PURE__ */ state(false);
		let triggerButton = /* @__PURE__ */ state(void 0);
		function openDialog() {
			set(opened, true);
			get(dialog).showModal();
		}
		function hideDialog() {
			get(dialog).close();
			set(opened, false);
			get(triggerButton)?.focus();
		}
		function handleDialogCancel() {
			set(opened, false);
			get(triggerButton)?.focus();
		}
		var $$exports = {
			get regionId() {
				return regionId();
			},
			set regionId($$value = "") {
				regionId($$value);
				flushSync();
			},
			get ajaxId() {
				return ajaxId();
			},
			set ajaxId($$value = "") {
				ajaxId($$value);
				flushSync();
			},
			get useAms() {
				return useAms();
			},
			set useAms($$value = false) {
				useAms($$value);
				flushSync();
			},
			get amsUrl() {
				return amsUrl();
			},
			set amsUrl($$value = "") {
				amsUrl($$value);
				flushSync();
			},
			get userId() {
				return userId();
			},
			set userId($$value = "") {
				userId($$value);
				flushSync();
			},
			get displayMode() {
				return displayMode();
			},
			set displayMode($$value = "dialog") {
				displayMode($$value);
				flushSync();
			},
			get chatMode() {
				return chatMode();
			},
			set chatMode($$value = "user") {
				chatMode($$value);
				flushSync();
			},
			get singleChatMode() {
				return singleChatMode();
			},
			set singleChatMode($$value = false) {
				singleChatMode($$value);
				flushSync();
			},
			get roomId() {
				return roomId();
			},
			set roomId($$value = "") {
				roomId($$value);
				flushSync();
			},
			get maxHeight() {
				return maxHeight();
			},
			set maxHeight($$value = "") {
				maxHeight($$value);
				flushSync();
			},
			get agentCode() {
				return agentCode();
			},
			set agentCode($$value = "") {
				agentCode($$value);
				flushSync();
			},
			get agentVersion() {
				return agentVersion();
			},
			set agentVersion($$value = null) {
				agentVersion($$value);
				flushSync();
			},
			get sessionId() {
				return sessionId();
			},
			set sessionId($$value = "") {
				sessionId($$value);
				flushSync();
			},
			get showReasoning() {
				return showReasoning();
			},
			set showReasoning($$value = false) {
				showReasoning($$value);
				flushSync();
			},
			get showTools() {
				return showTools();
			},
			set showTools($$value = false) {
				showTools($$value);
				flushSync();
			},
			get showMetadata() {
				return showMetadata();
			},
			set showMetadata($$value = false) {
				showMetadata($$value);
				flushSync();
			},
			get showDebug() {
				return showDebug();
			},
			set showDebug($$value = false) {
				showDebug($$value);
				flushSync();
			},
			get suggestedPrompts() {
				return suggestedPrompts();
			},
			set suggestedPrompts($$value = "") {
				suggestedPrompts($$value);
				flushSync();
			},
			get headerTitle() {
				return headerTitle();
			},
			set headerTitle($$value = "") {
				headerTitle($$value);
				flushSync();
			},
			get avatarIcon() {
				return avatarIcon();
			},
			set avatarIcon($$value = "") {
				avatarIcon($$value);
				flushSync();
			},
			get welcomeMessage() {
				return welcomeMessage();
			},
			set welcomeMessage($$value = "") {
				welcomeMessage($$value);
				flushSync();
			},
			get minHeight() {
				return minHeight();
			},
			set minHeight($$value = "") {
				minHeight($$value);
				flushSync();
			},
			get thinkingAnimation() {
				return thinkingAnimation();
			},
			set thinkingAnimation($$value = "") {
				thinkingAnimation($$value);
				flushSync();
			},
			get thinkingDetail() {
				return thinkingDetail();
			},
			set thinkingDetail($$value = "") {
				thinkingDetail($$value);
				flushSync();
			},
			get autoTitle() {
				return autoTitle();
			},
			set autoTitle($$value = false) {
				autoTitle($$value);
				flushSync();
			},
			get collectFeedback() {
				return collectFeedback();
			},
			set collectFeedback($$value = false) {
				collectFeedback($$value);
				flushSync();
			}
		};
		var div = root();
		var node = child(div);
		var consequent = ($$anchor) => {
			append($$anchor, root_1());
		};
		var consequent_2 = ($$anchor) => {
			var fragment = root_2();
			var button = first_child(fragment);
			bind_this(button, ($$value) => set(triggerButton, $$value), () => get(triggerButton));
			var dialog_1 = sibling(button, 2);
			var node_1 = child(dialog_1);
			var consequent_1 = ($$anchor) => {
				ChatWindow($$anchor, {
					hideDialog,
					get regionId() {
						return regionId();
					},
					get displayMode() {
						return displayMode();
					},
					get chatMode() {
						return chatMode();
					},
					get singleChatMode() {
						return singleChatMode();
					},
					get agentCode() {
						return agentCode();
					},
					get agentVersion() {
						return agentVersion();
					},
					get sessionId() {
						return sessionId();
					},
					get showReasoning() {
						return showReasoning();
					},
					get showTools() {
						return showTools();
					},
					get showMetadata() {
						return showMetadata();
					},
					get showDebug() {
						return showDebug();
					},
					get suggestedPrompts() {
						return suggestedPrompts();
					},
					get headerTitle() {
						return headerTitle();
					},
					get avatarIcon() {
						return avatarIcon();
					},
					get welcomeMessage() {
						return welcomeMessage();
					},
					get minHeight() {
						return minHeight();
					},
					get thinkingAnimation() {
						return thinkingAnimation();
					},
					get thinkingDetail() {
						return thinkingDetail();
					},
					get autoTitle() {
						return autoTitle();
					},
					get collectFeedback() {
						return collectFeedback();
					}
				});
			};
			if_block(node_1, ($$render) => {
				if (get(opened)) $$render(consequent_1);
			});
			reset(dialog_1);
			bind_this(dialog_1, ($$value) => set(dialog, $$value), () => get(dialog));
			template_effect(() => set_attribute(button, "id", `${regionId()}-chat-button`));
			delegated("click", button, openDialog);
			event("cancel", dialog_1, handleDialogCancel);
			append($$anchor, fragment);
		};
		var alternate = ($$anchor) => {
			ChatWindow($$anchor, {
				get regionId() {
					return regionId();
				},
				get displayMode() {
					return displayMode();
				},
				get chatMode() {
					return chatMode();
				},
				get singleChatMode() {
					return singleChatMode();
				},
				get agentCode() {
					return agentCode();
				},
				get agentVersion() {
					return agentVersion();
				},
				get sessionId() {
					return sessionId();
				},
				get showReasoning() {
					return showReasoning();
				},
				get showTools() {
					return showTools();
				},
				get showMetadata() {
					return showMetadata();
				},
				get showDebug() {
					return showDebug();
				},
				get suggestedPrompts() {
					return suggestedPrompts();
				},
				get headerTitle() {
					return headerTitle();
				},
				get avatarIcon() {
					return avatarIcon();
				},
				get welcomeMessage() {
					return welcomeMessage();
				},
				get minHeight() {
					return minHeight();
				},
				get thinkingAnimation() {
					return thinkingAnimation();
				},
				get thinkingDetail() {
					return thinkingDetail();
				},
				get autoTitle() {
					return autoTitle();
				},
				get collectFeedback() {
					return collectFeedback();
				}
			});
		};
		if_block(node, ($$render) => {
			if (!get(initialized)) $$render(consequent);
			else if (displayMode() === "dialog") $$render(consequent_2, 1);
			else $$render(alternate, -1);
		});
		reset(div);
		bind_this(div, ($$value) => set(chatEl, $$value), () => get(chatEl));
		template_effect(() => set_attribute(div, "id", regionId()));
		append($$anchor, div);
		return pop($$exports);
	}
	delegate(["click"]);
	customElements.define("uc-apex-chat", create_custom_element(APEXchat, {
		regionId: {},
		ajaxId: {},
		useAms: {},
		amsUrl: {},
		userId: {},
		displayMode: {},
		chatMode: {},
		singleChatMode: {},
		roomId: {},
		maxHeight: {},
		agentCode: {},
		agentVersion: {},
		sessionId: {},
		showReasoning: {},
		showTools: {},
		showMetadata: {},
		showDebug: {},
		suggestedPrompts: {},
		headerTitle: {},
		avatarIcon: {},
		welcomeMessage: {},
		minHeight: {},
		thinkingAnimation: {},
		thinkingDetail: {},
		autoTitle: {},
		collectFeedback: {}
	}, [], []));
	//#endregion
	return APEXchat;
})();
