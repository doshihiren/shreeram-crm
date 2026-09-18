<?php

namespace App\Http\Controllers\Api;

use App\Enums\UserRole;
use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Password;

class UserController extends Controller
{
    public function index(Request $request): AnonymousResourceCollection
    {
        abort_unless($request->user()->hasPermission('users.manage'), 403);

        $users = User::query()
            ->when($request->filled('role'), fn ($q) => $q->where('role', $request->string('role')))
            ->orderBy('name')
            ->paginate(min((int) $request->integer('per_page', 20), 50));

        return UserResource::collection($users);
    }

    public function store(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('users.manage'), 403);

        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'email', 'max:255', 'unique:users,email'],
            'mobile' => ['nullable', 'string', 'max:32'],
            'password' => ['required', Password::defaults()],
            'role' => ['required', Rule::enum(UserRole::class)],
        ]);

        if ($data['role'] === UserRole::Owner->value && ! $request->user()->isOwner()) {
            return response()->json(['message' => 'Only OWNER can create OWNER users.'], 403);
        }

        $user = User::query()->create([
            ...$data,
            'is_active' => true,
        ]);

        AuditLog::query()->create([
            'actor_id' => $request->user()->id,
            'action' => 'users.create',
            'entity_type' => User::class,
            'entity_id' => $user->id,
            'ip_address' => $request->ip(),
            'meta' => ['role' => $user->role->value],
        ]);

        return response()->json(['data' => new UserResource($user)], 201);
    }

    public function update(Request $request, User $user): UserResource
    {
        abort_unless($request->user()->hasPermission('users.manage'), 403);

        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'email' => ['sometimes', 'email', 'max:255', Rule::unique('users', 'email')->ignore($user->id)],
            'mobile' => ['nullable', 'string', 'max:32'],
            'password' => ['nullable', Password::defaults()],
            'is_active' => ['sometimes', 'boolean'],
            'role' => ['sometimes', Rule::enum(UserRole::class)],
        ]);

        if (isset($data['role'])) {
            abort_unless($request->user()->hasPermission('users.manage_roles') || $request->user()->isOwner(), 403);
            if ($data['role'] === UserRole::Owner->value && ! $request->user()->isOwner()) {
                abort(403, 'Only OWNER can assign OWNER role.');
            }
        }

        if (empty($data['password'])) {
            unset($data['password']);
        }

        $user->update($data);

        return new UserResource($user->fresh());
    }
}
