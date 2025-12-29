# NestJS Controllers Skill

Build REST controllers following NestJS and API Gateway patterns.

## Quick Pattern

```typescript
import { Body, Controller, Delete, Get, Param, Post, Put } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse } from '@nestjs/swagger';
import { UserService } from './user.service';
import { CreateUserDTO } from './dtos/create-user.dto';
import { Auth } from '../auth/decorator/auth.decorator';
import { AuthType } from 'src/constants/auth';

@ApiTags('users')
@Controller('users')
export class UserController {
  constructor(private readonly userService: UserService) {}

  @Get()
  @ApiOperation({ summary: 'List all users' })
  @ApiResponse({ status: 200, description: 'Users retrieved' })
  async getAll() {
    return this.userService.findAll();
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get user by ID' })
  async getById(@Param('id') id: string) {
    return this.userService.findById(id);
  }

  @Post()
  @Auth(AuthType.None) // Public endpoint
  @ApiOperation({ summary: 'Create new user' })
  async create(@Body() createUserDTO: CreateUserDTO) {
    return this.userService.create(createUserDTO);
  }

  @Put(':id')
  @Auth(AuthType.Bearer) // Protected endpoint
  @ApiOperation({ summary: 'Update user' })
  async update(@Param('id') id: string, @Body() updateDTO: CreateUserDTO) {
    return this.userService.update(id, updateDTO);
  }

  @Delete(':id')
  @Auth(AuthType.Bearer)
  @ApiOperation({ summary: 'Delete user' })
  async delete(@Param('id') id: string) {
    return this.userService.delete(id);
  }
}
```

## Patterns

### 1. REST CRUD Controller

**When:** Standard REST endpoints for entity management

```typescript
@Controller('posts')
export class PostController {
  constructor(private readonly postService: PostService) {}

  @Get() // GET /posts
  findAll() { return this.postService.findAll(); }

  @Get(':id') // GET /posts/:id
  findById(@Param('id') id: string) { }

  @Post() // POST /posts
  create(@Body() dto: CreatePostDTO) { }

  @Put(':id') // PUT /posts/:id
  update(@Param('id') id: string, @Body() dto: UpdatePostDTO) { }

  @Patch(':id') // PATCH /posts/:id (partial update)
  patch(@Param('id') id: string, @Body() dto: Partial<UpdatePostDTO>) { }

  @Delete(':id') // DELETE /posts/:id
  delete(@Param('id') id: string) { }
}
```

### 2. Controller with Auth Decorator

**When:** Gateway pattern with custom auth decorator

```typescript
import { Auth } from '../auth/decorator/auth.decorator';
import { AuthType } from 'src/constants/auth';

@Controller('admin')
export class AdminController {
  @Get()
  @Auth(AuthType.None) // Public
  public() { }

  @Post()
  @Auth(AuthType.Bearer) // Requires JWT token
  protected() { }

  @Delete()
  @Auth(AuthType.ApiKey) // Requires API key
  restrictedDelete() { }
}
```

### 3. Nested Resources

**When:** Parent-child resource relationships

```typescript
@Controller('users/:userId/posts')
export class UserPostController {
  constructor(private readonly postService: PostService) {}

  @Get() // GET /users/:userId/posts
  findUserPosts(@Param('userId') userId: string) {
    return this.postService.findByUserId(userId);
  }

  @Post() // POST /users/:userId/posts
  createUserPost(
    @Param('userId') userId: string,
    @Body() createDTO: CreatePostDTO
  ) {
    return this.postService.create(userId, createDTO);
  }
}
```

### 4. Controller with Query Filtering

**When:** List endpoints with optional filters

```typescript
import { Query } from '@nestjs/common';

@Controller('products')
export class ProductController {
  @Get()
  search(
    @Query('category') category?: string,
    @Query('minPrice') minPrice?: number,
    @Query('maxPrice') maxPrice?: number,
    @Query('page') page: number = 1,
    @Query('limit') limit: number = 10
  ) {
    return this.productService.search({
      category,
      minPrice,
      maxPrice,
      page,
      limit
    });
  }
}
```

### 5. Controller with Response Transformation

**When:** Standardized API response format

```typescript
import { Serializer } from 'src/common/interceptors/serializer.interceptor';
import { UserDTO } from './dtos/user.dto';

@Controller('users')
@UseInterceptors(new Serializer(UserDTO))
export class UserController {
  @Get(':id')
  @ApiResponse({ type: UserDTO })
  async getById(@Param('id') id: string) {
    // Returns plain object, interceptor transforms to UserDTO
    return this.userService.findById(id);
  }
}
```

### 6. File Upload Controller

**When:** Handling file uploads

```typescript
import { UseInterceptors, UploadedFile } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';

@Controller('files')
export class FileController {
  constructor(private readonly fileService: FileService) {}

  @Post('upload')
  @UseInterceptors(FileInterceptor('file'))
  async uploadFile(@UploadedFile() file: Express.Multer.File) {
    return this.fileService.save(file);
  }
}
```

## Decorators & Metadata

### Request Decorators

| Decorator | Use | Example |
|-----------|-----|---------|
| `@Get()`, `@Post()`, etc. | HTTP method + path | `@Get('users/:id')` |
| `@Param()` | Route parameter | `@Param('id') id: string` |
| `@Query()` | Query string | `@Query('page') page: number` |
| `@Body()` | Request body | `@Body() dto: CreateDTO` |
| `@Headers()` | HTTP headers | `@Headers('authorization') token: string` |
| `@Req()` / `@Res()` | Raw request/response | For advanced cases |

### Response Decorators

| Decorator | Use |
|-----------|-----|
| `@HttpCode()` | Override HTTP status code |
| `@Header()` | Set response header |
| `@Redirect()` | Redirect to URL |

### Example

```typescript
@Post('activate')
@HttpCode(202) // Return 202 Accepted instead of 201 Created
@Header('X-Custom-Header', 'value')
async activateUser(@Body() dto: ActivateDTO) {
  return this.userService.activate(dto);
}
```

## Swagger Documentation

```typescript
@ApiTags('Auth')
@Controller('auth')
export class AuthController {
  @Post('sign-in')
  @Auth(AuthType.None)
  @ApiOperation({
    summary: 'Sign in user',
    description: 'Sign in with email and password to get access token'
  })
  @ApiResponse({
    status: 200,
    description: 'User successfully signed in',
    schema: {
      example: {
        data: {
          accessToken: { token: 'jwt...', expiresIn: 3600 },
          user: { sub: '1', email: 'user@example.com' }
        },
        statusCode: 200
      }
    }
  })
  @ApiResponse({
    status: 401,
    description: 'Invalid credentials'
  })
  async signIn(@Body() signInDTO: SignInDTO) {
    return this.authService.signIn(signInDTO);
  }
}
```

## Testing Controllers

```typescript
describe('UserController', () => {
  let controller: UserController;
  let service: UserService;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      controllers: [UserController],
      providers: [
        {
          provide: UserService,
          useValue: {
            findAll: jest.fn(),
            findById: jest.fn(),
            create: jest.fn(),
          }
        }
      ]
    }).compile();

    controller = module.get(UserController);
    service = module.get(UserService);
  });

  describe('getAll', () => {
    it('should return array of users', async () => {
      const users = [{ id: '1', name: 'John' }];
      jest.spyOn(service, 'findAll').mockResolvedValue(users);

      expect(await controller.getAll()).toBe(users);
      expect(service.findAll).toHaveBeenCalled();
    });
  });
});
```

## Anti-Patterns

❌ Business logic in controller
```typescript
@Post('users')
createUser(@Body() dto: CreateUserDTO) {
  // Don't do complex logic here
  const user = new User();
  user.name = dto.name;
  user.email = dto.email;
  user.createdAt = new Date();
  return user;
}
```

✓ Delegate to service
```typescript
@Post('users')
createUser(@Body() dto: CreateUserDTO) {
  return this.userService.create(dto);
}
```

❌ No validation
```typescript
@Post('users')
createUser(@Body() dto: any) { } // ✗ Untyped
```

✓ Type and validate
```typescript
@Post('users')
createUser(@Body() dto: CreateUserDTO) { } // ✓ Typed
```

❌ Missing error handling
```typescript
@Get(':id')
async getUser(@Param('id') id: string) {
  return this.userService.findById(id); // May throw!
}
```

✓ Handle errors
```typescript
@Get(':id')
@ApiResponse({ status: 404, description: 'User not found' })
async getUser(@Param('id') id: string) {
  const user = await this.userService.findById(id);
  if (!user) throw new NotFoundException();
  return user;
}
```

## Token Cost

- Invocation: 100 tokens
- CRUD pattern: 150-200 tokens
- Swagger docs: 100-150 tokens
- Context7 (if needed): 1000-1500 tokens
- **Total:** 350-2000 tokens depending on complexity

## When to Lookup Context7

- Advanced routing with async path parameters
- Complex request/response transformation
- Integrating multiple interceptors
- Custom content negotiation (XML, CSV)
