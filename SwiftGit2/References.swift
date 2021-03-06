//
//  References.swift
//  SwiftGit2
//
//  Created by Matt Diephouse on 1/2/15.
//  Copyright (c) 2015 GitHub, Inc. All rights reserved.
//

/// A reference to a git object.
public protocol ReferenceType {
	/// The full name of the reference (e.g., `refs/heads/master`).
	var longName: String { get }
	
	/// The short human-readable name of the reference if one exists (e.g., `master`).
	var shortName: String? { get }
	
	/// The OID of the referenced object.
	var oid: OID { get }
}

public func ==<T: ReferenceType>(lhs: T, rhs: T) -> Bool {
	return lhs.longName == rhs.longName
		&& lhs.oid == rhs.oid
}

/// Create a Reference, Branch, or TagReference from a libgit2 `git_reference`.
internal func referenceWithLibGit2Reference(pointer: COpaquePointer) -> ReferenceType {
	if git_reference_is_branch(pointer) != 0 || git_reference_is_remote(pointer) != 0 {
		return Branch(pointer)!
	} else if git_reference_is_tag(pointer) != 0 {
		return TagReference(pointer)!
	} else {
		return Reference(pointer)
	}
}

/// A generic reference to a git object.
public struct Reference: ReferenceType {
	/// The full name of the reference (e.g., `refs/heads/master`).
	public let longName: String
	
	/// The short human-readable name of the reference if one exists (e.g., `master`).
	public let shortName: String?
	
	/// The OID of the referenced object.
	public let oid: OID
	
	/// Create an instance with a libgit2 `git_reference` object.
	public init(_ pointer: COpaquePointer) {
		let shorthand = String.fromCString(git_reference_shorthand(pointer))!
		longName = String.fromCString(git_reference_name(pointer))!
		shortName = (shorthand == longName ? nil : shorthand)
		oid = OID(git_reference_target(pointer).memory)
	}
}

extension Reference: Hashable {
	public var hashValue: Int {
		return longName.hashValue ^ oid.hashValue
	}
}

/// A git branch.
public struct Branch: ReferenceType {
	/// The full name of the reference (e.g., `refs/heads/master`).
	public let longName: String
	
	/// The short human-readable name of the branch (e.g., `master`).
	public let name: String
	
	/// A pointer to the referenced commit.
	public let commit: PointerTo<Commit>
	
	// MARK: Derived Properties
	
	/// The short human-readable name of the branch (e.g., `master`).
	///
	/// This is the same as `name`, but is declared with an Optional type to adhere to
	/// `ReferenceType`.
	public var shortName: String? { return name }
	
	/// The OID of the referenced object.
	///
	/// This is the same as `commit.oid`, but is declared here to adhere to `ReferenceType`.
	public var oid: OID { return commit.oid }
	
	/// Whether the branch is a local branch.
	public var isLocal: Bool { return longName.hasPrefix("refs/heads/") }
	
	/// Whether the branch is a remote branch.
	public var isRemote: Bool { return longName.hasPrefix("refs/remotes/") }
	
	/// Create an instance with a libgit2 `git_reference` object.
	///
	/// Returns `nil` if the pointer isn't a branch.
	public init?(_ pointer: COpaquePointer) {
		let namePointer = UnsafeMutablePointer<UnsafePointer<Int8>>.alloc(1)
		let success = git_branch_name(namePointer, pointer)
		if success != GIT_OK.value {
			namePointer.dealloc(1)
			return nil
		}
		name = String.fromCString(namePointer.memory)!
		namePointer.dealloc(1)
		
		longName = String.fromCString(git_reference_name(pointer))!
		
		var oid: OID
		if git_reference_type(pointer).value == GIT_REF_SYMBOLIC.value {
			var resolved: COpaquePointer = nil
			let success = git_reference_resolve(&resolved, pointer)
			if success != GIT_OK.value {
				return nil
			}
			oid = OID(git_reference_target(resolved).memory)
			git_reference_free(resolved)
		} else {
			oid = OID(git_reference_target(pointer).memory)
		}
		commit = PointerTo<Commit>(oid)
	}
}

extension Branch: Hashable {
	public var hashValue: Int {
		return longName.hashValue ^ oid.hashValue
	}
}

/// A git tag reference, which can be either a lightweight tag or a Tag object.
public enum TagReference: ReferenceType {
	/// A lightweight tag, which is just a name and an OID.
	case Lightweight(String, OID)
	
	/// An annotated tag, which points to a Tag object.
	case Annotated(String, Tag)
	
	/// The full name of the reference (e.g., `refs/tags/my-tag`).
	public var longName: String {
		switch self {
		case let .Lightweight(name, _):
			return name
		case let .Annotated(name, _):
			return name
		}
	}
	
	/// The short human-readable name of the branch (e.g., `master`).
	public var name: String {
		return longName.substringFromIndex("refs/tags/".endIndex)
	}
	
	/// The OID of the target object.
	///
	/// If this is an annotated tag, the OID will be the tag's target.
	public var oid: OID {
		switch self {
		case let .Lightweight(_, oid):
			return oid
		case let .Annotated(_, tag):
			return tag.target.oid
		}
	}
	
	// MARK: Derived Properties
	
	/// The short human-readable name of the branch (e.g., `master`).
	///
	/// This is the same as `name`, but is declared with an Optional type to adhere to
	/// `ReferenceType`.
	public var shortName: String? { return name }
	
	/// Create an instance with a libgit2 `git_reference` object.
	///
	/// Returns `nil` if the pointer isn't a branch.
	public init?(_ pointer: COpaquePointer) {
		if git_reference_is_tag(pointer) == 0 {
			return nil;
		}
		
		let name = String.fromCString(git_reference_name(pointer))!
		let repo = git_reference_owner(pointer)
		var oid = git_reference_target(pointer).memory
		
		var pointer: COpaquePointer = nil
		let result = git_object_lookup(&pointer, repo, &oid, GIT_OBJ_TAG)
		if result == GIT_OK.value {
			self = .Annotated(name, Tag(pointer))
		} else {
			self = .Lightweight(name, OID(oid))
		}
		git_object_free(pointer)
	}
}

extension TagReference: Hashable {
	public var hashValue: Int {
		return longName.hashValue ^ oid.hashValue
	}
}

