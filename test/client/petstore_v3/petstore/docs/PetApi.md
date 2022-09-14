# PetApi

All URIs are relative to */v3*

Method | HTTP request | Description
------------- | ------------- | -------------
[**addPet**](PetApi.md#addPet) | **POST** /pet | Add a new pet to the store
[**deletePet**](PetApi.md#deletePet) | **DELETE** /pet/{petId} | Deletes a pet
[**findPetsByStatus**](PetApi.md#findPetsByStatus) | **GET** /pet/findByStatus | Finds Pets by status
[**findPetsByTags**](PetApi.md#findPetsByTags) | **GET** /pet/findByTags | Finds Pets by tags
[**getPetById**](PetApi.md#getPetById) | **GET** /pet/{petId} | Find pet by ID
[**updatePet**](PetApi.md#updatePet) | **PUT** /pet | Update an existing pet
[**updatePetWithForm**](PetApi.md#updatePetWithForm) | **POST** /pet/{petId} | Updates a pet in the store with form data
[**uploadFile**](PetApi.md#uploadFile) | **POST** /pet/{petId}/uploadImage | uploads an image


# **addPet**
> addPet(_api::PetApi, in_Pet::Pet; _mediaType=nothing) <br/>
> addPet(_api::PetApi, response_stream::Channel, in_Pet::Pet; _mediaType=nothing)

Add a new pet to the store

### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **PetApi** | API context | 
**in_Pet** | [**Pet**](Pet.md)| Pet object that needs to be added to the store | 

### Return type

 nothing

### Authorization

[petstore_auth](../README.md#petstore_auth)

### HTTP request headers

 - **Content-Type**: application/json, application/xml
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deletePet**
> deletePet(_api::PetApi, in_petId::Int64; in_api_key=nothing, _mediaType=nothing) <br/>
> deletePet(_api::PetApi, response_stream::Channel, in_petId::Int64; in_api_key=nothing, _mediaType=nothing)

Deletes a pet

### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **PetApi** | API context | 
**in_petId** | **Int64**| Pet id to delete | [default to nothing]

### Optional Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **in_api_key** | **String**|  | [default to nothing]

### Return type

 nothing

### Authorization

[petstore_auth](../README.md#petstore_auth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **findPetsByStatus**
> findPetsByStatus(_api::PetApi, in_status::Vector{String}; _mediaType=nothing) -> Vector{Pet}  <br/>
> findPetsByStatus(_api::PetApi, response_stream::Channel, in_status::Vector{String}; _mediaType=nothing) -> Vector{Pet} 

Finds Pets by status

Multiple status values can be provided with comma separated strings

### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **PetApi** | API context | 
**in_status** | [**Vector{String}**](String.md)| Status values that need to be considered for filter | [default to nothing]

### Return type

[**Vector{Pet}**](Pet.md)

### Authorization

[petstore_auth](../README.md#petstore_auth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/xml, application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **findPetsByTags**
> findPetsByTags(_api::PetApi, in_tags::Vector{String}; _mediaType=nothing) -> Vector{Pet}  <br/>
> findPetsByTags(_api::PetApi, response_stream::Channel, in_tags::Vector{String}; _mediaType=nothing) -> Vector{Pet} 

Finds Pets by tags

Multiple tags can be provided with comma separated strings. Use tag1, tag2, tag3 for testing.

### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **PetApi** | API context | 
**in_tags** | [**Vector{String}**](String.md)| Tags to filter by | [default to nothing]

### Return type

[**Vector{Pet}**](Pet.md)

### Authorization

[petstore_auth](../README.md#petstore_auth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/xml, application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getPetById**
> getPetById(_api::PetApi, in_petId::Int64; _mediaType=nothing) -> Pet  <br/>
> getPetById(_api::PetApi, response_stream::Channel, in_petId::Int64; _mediaType=nothing) -> Pet 

Find pet by ID

Returns a single pet

### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **PetApi** | API context | 
**in_petId** | **Int64**| ID of pet to return | [default to nothing]

### Return type

[**Pet**](Pet.md)

### Authorization

[api_key](../README.md#api_key)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/xml, application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updatePet**
> updatePet(_api::PetApi, in_Pet::Pet; _mediaType=nothing) <br/>
> updatePet(_api::PetApi, response_stream::Channel, in_Pet::Pet; _mediaType=nothing)

Update an existing pet

### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **PetApi** | API context | 
**in_Pet** | [**Pet**](Pet.md)| Pet object that needs to be added to the store | 

### Return type

 nothing

### Authorization

[petstore_auth](../README.md#petstore_auth)

### HTTP request headers

 - **Content-Type**: application/json, application/xml
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updatePetWithForm**
> updatePetWithForm(_api::PetApi, in_petId::Int64; in_name=nothing, in_status=nothing, _mediaType=nothing) <br/>
> updatePetWithForm(_api::PetApi, response_stream::Channel, in_petId::Int64; in_name=nothing, in_status=nothing, _mediaType=nothing)

Updates a pet in the store with form data

### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **PetApi** | API context | 
**in_petId** | **Int64**| ID of pet that needs to be updated | [default to nothing]

### Optional Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **in_name** | **String**| Updated name of the pet | [default to nothing]
 **in_status** | **String**| Updated status of the pet | [default to nothing]

### Return type

 nothing

### Authorization

[petstore_auth](../README.md#petstore_auth)

### HTTP request headers

 - **Content-Type**: application/x-www-form-urlencoded
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **uploadFile**
> uploadFile(_api::PetApi, in_petId::Int64; in_additionalMetadata=nothing, in_file=nothing, _mediaType=nothing) -> ApiResponse  <br/>
> uploadFile(_api::PetApi, response_stream::Channel, in_petId::Int64; in_additionalMetadata=nothing, in_file=nothing, _mediaType=nothing) -> ApiResponse 

uploads an image

### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **PetApi** | API context | 
**in_petId** | **Int64**| ID of pet to update | [default to nothing]

### Optional Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **in_additionalMetadata** | **String**| Additional data to pass to server | [default to nothing]
 **in_file** | **String****String**| file to upload | [default to nothing]

### Return type

[**ApiResponse**](ApiResponse.md)

### Authorization

[petstore_auth](../README.md#petstore_auth)

### HTTP request headers

 - **Content-Type**: multipart/form-data
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

