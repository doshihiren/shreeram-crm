<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    public function login(Request $request): JsonResponse
    {
        $credentials = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
        ]);

        /** @var User|null $user */
        $user = User::query()->where('email', $credentials['email'])->first();
        if (! $user || ! Hash::check($credentials['password'], $user->password)) {
            throw ValidationException::withMessages([
                'email' => ['The provided credentials are incorrect.'],
            ]);
        }

        if (! $user->is_active) {
            return response()->json(['message' => 'Account is inactive.'], 403);
        }

        $user->forceFill(['last_login_at' => now()])->save();
        $token = $user->createToken('flutter')->plainTextToken;

        AuditLog::query()->create([
            'actor_id' => $user->id,
            'action' => 'auth.login',
            'entity_type' => User::class,
            'entity_id' => $user->id,
            'ip_address' => $request->ip(),
            'user_agent' => (string) $request->userAgent(),
        ]);

        return response()->json([
            'token' => $token,
            'token_type' => 'Bearer',
            'user' => (new UserResource($user))->resolve(),
        ]);
    }

    public function me(Request $request): JsonResponse
    {
        return response()->json((new UserResource($request->user()))->resolve());
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()?->currentAccessToken()?->delete();

        return response()->json(['message' => 'Logged out.']);
    }
}
